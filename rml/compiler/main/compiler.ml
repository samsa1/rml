(**********************************************************************)
(*                                                                    *)
(*                           ReactiveML                               *)
(*                    http://reactiveML.org                           *)
(*                    http://rml.inria.fr                             *)
(*                                                                    *)
(*                          Louis Mandel                              *)
(*                                                                    *)
(*  Copyright 2002, 2007 Louis Mandel.  All rights reserved.          *)
(*  This file is distributed under the terms of the Q Public License  *)
(*  version 1.0.                                                      *)
(*                                                                    *)
(*  ReactiveML has been done in the following labs:                   *)
(*  - theme SPI, Laboratoire d'Informatique de Paris 6 (2002-2005)    *)
(*  - Verimag, CNRS Grenoble (2005-2006)                              *)
(*  - projet Moscova, INRIA Rocquencourt (2006-2007)                  *)
(*                                                                    *)
(**********************************************************************)

(* file: compiler.ml *)

(* Warning: *)
(* This file is based on the original version of compiler.ml *)
(* from the Lucid Synchrone version 2 distribution, Lip6     *)

(* first modification: 2004-05-06 *)
(* modified by: Louis Mandel      *)

(* $Id$ *)

open Misc
open Errors


(* compiling a file. Two steps. *)
(* - Front-end: - Parsing
                - Typing
                - Static analysis
                - emission of the intermediate rml code *)
(* - Back-end: - generation of caml code for the whole file *)

(* [info_chan] is the channel where static informations are emitted *)
(* [out_chan] is the channel where the generated code is emitted *)

(*module Front_end_timer = Timer (struct let name = "Front-end" end)*)
(*module Back_end_timer = Timer (struct let name = "Back-end" end)*)
module Parse_timer = Timer (struct let name = "Parsing" end)
module External_timer = Timer (struct let name = "External" end)
module Parse2reac_timer = Timer (struct let name = "Parse2reac" end)
module Typing_timer = Timer (struct let name = "Typing" end)
module Static_timer = Timer (struct let name = "Static" end)
module Other_analysis_timer = Timer (struct let name = "Other_analysis" end)
module Reac2lco_timer = Timer (struct let name = "Reac2lco" end)
module Reac2lk_timer = Timer (struct let name = "Reac2lk" end)
module Lco2caml_timer = Timer (struct let name = "Lco2caml" end)
module Lk2caml_timer = Timer (struct let name = "Lk2caml" end)
module Optimization_timer = Timer (struct let name = "Optimization" end)


(* front-end *)
let compile_implementation_front_end info_fmt itf impl_list =
  let rml_table = ref [] in
  let compile_one_phrase impl =

    (* Display the parse code *)
    if !dparse then
      begin
	Parse_printer.impl_item 0 info_fmt impl;
      end;

    (* producing rml code (and openning of modules) *)
    Parse2reac_timer.start();
    let rml_code = Parse2reac.translate_impl_item info_fmt impl in
    let rml_code = Reac2reac.impl_map Reac2reac.translate_merge rml_code in
    Parse2reac_timer.time();

    Optimization_timer.start();
    let rml_code =
      if !nary_optimization then
	Reac2reac.impl_map Reac2reac.binary2nary rml_code
      else
	rml_code
    in
    Optimization_timer.time();

    (* typing *)
    Typing_timer.start();
    Typing.type_impl_item info_fmt rml_code;
    Typing_timer.time();

    (* static analysis *)
    Static_timer.start();
    Static.static info_fmt rml_code;
    Static_timer.time();

    Optimization_timer.start();
    let rml_code =
      if !static_optimization then
	Reac2reac.impl_map Reac2reac.dynamic2static rml_code
      else
	rml_code
    in
    Optimization_timer.time();

    (* Instantaneous loop *)
    Other_analysis_timer.start();
    Wf_rec.check rml_code;
    if !instantaneous_loop_warning then
      Instantaneous_loop.instantaneous_loop rml_code;
    Other_analysis_timer.time();

    ignore
      (Reac2reac.impl_map
	 (fun e ->  Annot.Sstatic.record (Annot.Ti_expr e); e)
	 rml_code);

    (* for option *)
    Optimization_timer.start();
    let rml_code =
      if !for_optimization then
	Reac2reac.impl_map Reac2reac.for2loop_n rml_code
      else
	rml_code
    in
    Optimization_timer.time();

    rml_table :=  rml_code :: !rml_table;
  in

  (* compilation of the whole file *)
  List.iter compile_one_phrase impl_list;


  (* XXX A FAIRE XXX : verifier s'il y a un .rmli (ou un .mli) pour verifier *)
  (* la coherence et voir s'il faut ecrir l'insterface.                      *)
(*
  if Sys.file_exists (filename ^ ".rmli")
  ||  Sys.file_exists (filename ^ ".mli")
  then begin
    if not (Sys.file_exists (filename ^ ".rzi")) then begin
      raise(Error(Location.in_file mlifile, Interface_not_compiled mlifile))
    end else begin
      let dclsig = Env.read_signature modulename cmifile in
      Includemod.compunit "(obtained by packing)" sg mlifile dclsig
    end
  end else begin
*)
    (* write interface *)
    Misc.opt_iter Modules.write_compiled_interface itf;
(*
  end;
*)
  (* we return the rml code *)
  List.rev !rml_table


(* back-end *)
let compile_implementation_back_end_buf info_fmt module_name rml_table =
  let lk_table = ref [] in
  let lco_table = ref [] in
  let caml_table = ref [] in

  let lk_compile_one_phrase impl =

    (* translation into lk code *)
    Reac2lk_timer.start();
    let lk_code = Reac2lk.translate_impl_item info_fmt impl in
    lk_table := lk_code :: !lk_table;
    Reac2lk_timer.time();

    (* producing caml code *)
    Lk2caml_timer.start();
    let caml_code = Lk2caml.translate_impl_item info_fmt lk_code in
    Lk2caml_timer.time();

    (* Optimization *)
    Optimization_timer.start();
    let caml_code =
      if !const_optimization then
	Caml2caml.constant_propagation_impl caml_code
      else
	caml_code
    in
    Optimization_timer.time();

    caml_table := caml_code :: !caml_table

  in

  let lco_compile_one_phrase impl =

    (* translation into lco code *)
    Reac2lco_timer.start();
    let lco_code = Reac2lco.translate_impl_item info_fmt impl in
    lco_table := lco_code :: !lco_table;
    Reac2lco_timer.time();

    (* producing caml code *)
    Lco2caml_timer.start();
    let caml_code = Lco2caml.translate_impl_item info_fmt lco_code in
    Lco2caml_timer.time();

    (* Optimization *)
    Optimization_timer.start();
    let caml_code =
      if !const_optimization then
	Caml2caml.constant_propagation_impl caml_code
      else
	caml_code
    in
    Optimization_timer.time();

    caml_table := caml_code :: !caml_table
  in

  (* selection of the back-end *)
  let compile_one_phrase =
    match !translation with
    | Lk -> lk_compile_one_phrase
    | Lco -> lco_compile_one_phrase
  in

  (* compilation of the whole table *)
  List.iter compile_one_phrase rml_table;

  (* emit the caml code *)
  List.map
    (Print_caml_src.output_impl_decl_string module_name)
    (List.rev !caml_table)

let compile_implementation_back_end info_chan out_chan module_name rml_table =
  let strings = compile_implementation_back_end_buf info_chan module_name rml_table in
  List.iter (output_string out_chan) strings

(* the main functions *)
let compile_implementation module_name filename =
  (* input and output files *)
  let source_name = filename ^ ".rml"
  and obj_interf_name = filename ^ ".rzi"
  and obj_name = filename ^ ".ml"
  and tannot_name = filename ^ ".tannot"
  and sannot_name = filename ^ ".sannot"
  and module_name = String.capitalize filename  in

  let ic = open_in source_name in
  let itf = Some (open_out_bin obj_interf_name) in
  let info_fmt = Format.std_formatter in

  try
(*    Front_end_timer.start();*)

    (* load predefined base types *)
    Modules.start_compiling_interface module_name;
    Initialization.load_initial_modules ();

    let lexbuf = Lexing.from_channel ic in
    Location.init lexbuf source_name;

    (* parsing of the file *)
    Parse_timer.start();
    let decl_list = Parse.implementation lexbuf in
    Parse_timer.time();

    (* expend externals *)
    External_timer.start();
    let decl_list = List.map External.expend decl_list in
    External_timer.time();

    (* front-end *)
    let intermediate_code = compile_implementation_front_end info_fmt itf
	decl_list in
    Misc.opt_iter close_out itf;

    if Sys.file_exists (filename ^ ".rmli")
       ||  Sys.file_exists (filename ^ ".mli")
    then ()
    else Typing.check_nongen_values intermediate_code;

(*    Front_end_timer.time ();*)

    (* back-end *)
    if not !no_link then
      begin
(*	Back_end_timer.start ();*)

	let out_chan = open_out obj_name in
	output_string out_chan
	  ("(* THIS FILE IS GENERATED. *)\n"^
	   "(* "^(Array.fold_right (fun s cmd -> s^" "^cmd) Sys.argv " ")^
	   "*)\n\n");
        (* selection of the interpreter *)
	output_string out_chan ("open "^ !interpreter_impl ^";;\n");

        (* the implementation *)
	compile_implementation_back_end info_fmt out_chan
	  module_name intermediate_code;

        (* main process *)
	if !simulation_process <> "" then
	  begin
	    output_string out_chan ("module Rml_machine = Rml_machine.M("^
				    !interpreter_module ^");;\n");
	    let main =
	      try
		Modules.pfind_value_desc
		  (Parse_ident.Pident !simulation_process)
	      with Modules.Desc_not_found ->
		unbound_main !simulation_process
	    in
	    let main_id = Ident.name main.Global.gi.Global_ident.id in
 	    if not (Typing.is_unit_process (Global.info main)) then
	      bad_type_main !simulation_process (Global.info main);
	    match !number_of_instant >= 0, !sampling >= 0.0 with
	    | true, true ->
		output_string out_chan
		  ("let _ = Rml_machine.rml_exec_n_sampling "^
		   main_id^" "^(string_of_int !number_of_instant)^" "^
		   (string_of_float !sampling)^"\n")
	    | true, false ->
		output_string out_chan
		  ("let _ = Rml_machine.rml_exec_n "^
		   main_id^" "^(string_of_int !number_of_instant)^"\n")
	    | false, true ->
		output_string out_chan
		  ("let _ = Rml_machine.rml_exec_sampling "^
		   main_id^" "^(string_of_float !sampling)^"\n")
	    | false, false ->
		output_string out_chan
		  ("let _ = Rml_machine.rml_exec "^main_id^"\n")
	  end;
	close_out out_chan;
(*	Back_end_timer.time()*)

      end;

   (* write types annotation *)
    Annot.Stypes.dump tannot_name;
    Annot.Sstatic.dump sannot_name;

    close_in ic;
  with
    x ->
      Annot.Stypes.dump tannot_name;
      Annot.Sstatic.dump sannot_name;
      close_in ic;
      raise x


(* compiling an interface *)
(* front-end *)
let compile_interface_front_end info_fmt itf intf_list =
  let rml_table = ref [] in
  let compile_one_phrase phr =
    (* producing rml code (and openning of modules) *)
    let rml_code = Parse2reac.translate_intf_item info_fmt phr in
    rml_table := rml_code :: !rml_table;

    (* typing *)
    Typing.type_intf_item info_fmt rml_code;
  in

  (* compilation of the whole file *)
  List.iter compile_one_phrase intf_list;

  (* write interface *)
  Modules.write_compiled_interface itf;
  close_out itf;

  (* we return the rml code *)
  List.rev !rml_table

(* back-end *)
let compile_interface_back_end info_fmt out_chan module_name rml_table =
  let lk_table = ref [] in
  let lco_table = ref [] in
  let caml_table = ref [] in

  let lk_compile_one_phrase intf =

    (* translation into lk code *)
    let lk_code = Reac2lk.translate_intf_item info_fmt intf in
    lk_table := lk_code :: !lk_table;

    (* producing caml code *)
    let caml_code = Lk2caml.translate_intf_item info_fmt lk_code in
    caml_table := caml_code :: !caml_table;
  in

  let lco_compile_one_phrase intf =

    (* translation into lco code *)
    let lco_code = Reac2lco.translate_intf_item info_fmt intf in
    lco_table := lco_code :: !lco_table;

    (* producing caml code *)
    let caml_code = Lco2caml.translate_intf_item info_fmt lco_code in
    caml_table := caml_code :: !caml_table;
  in

  (* selection of the back-end *)
  let compile_one_phrase =
    match !translation with
    | Lk -> (* assert false *) lk_compile_one_phrase
    | Lco -> lco_compile_one_phrase
  in

  (* compilation of the whole table *)
  List.iter compile_one_phrase rml_table;

  (* emit the caml code *)
  List.iter
    (Print_caml_src.output_intf_decl out_chan module_name)
    (List.rev !caml_table)


(* the main functions *)
let compile_interface parse module_name filename filename_end =
  (* input and output files *)
  let source_name = filename ^ filename_end
  and obj_interf_name = filename ^ ".rzi"
  and obj_name = filename ^ ".mli"
  and module_name = String.capitalize filename  in

  let ic = open_in source_name in
  let itf = open_out_bin obj_interf_name in
  let info_fmt = Format.std_formatter in

  try

    (* load predefined base types *)
    Modules.start_compiling_interface module_name;
    Initialization.load_initial_modules ();

    let lexbuf = Lexing.from_channel ic in
    Location.init lexbuf source_name;

    (* parsing of the file *)
    let decl_list = parse lexbuf in

    (* front-end *)
    let intermediate_code = compile_interface_front_end info_fmt itf
	decl_list in

    (* back-end *)
    if (not !no_link) then
      begin
	let out_chan = open_out obj_name in
        (* selection of the interpreter *)
	output_string out_chan ("open "^ !interpreter_impl ^";;\n");

        (* the interface *)
	compile_interface_back_end info_fmt out_chan
	  module_name intermediate_code;

	close_out out_chan
      end;
    close_in ic;

  with
    x ->
      close_in ic;
      raise x


(* compiling a scalar interface *)
let compile_scalar_interface module_name filename =
  no_link := true;
  compile_interface Parse.interface module_name filename ".mli"

(* compiling a ReactiveML interface *)
let compile_interface module_name filename =
  compile_interface Parse.interface module_name filename ".rmli"

