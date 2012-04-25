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

(* file: interactive.ml *)
(* created: 2005-06-11  *)
(* author: Louis Mandel *)

(* $Id$ *)

(* compile a list of declarations *)
let compile_decl_list module_name itf info_chan out_chan decl_list =
  (* expend externals *)
  let decl_list = List.map External.expend decl_list in
  (* front-end *)
  let intermediate_code =
    Compiler.compile_implementation_front_end info_chan itf decl_list
  in
  (* the implementation *)
  Compiler.compile_implementation_back_end info_chan out_chan module_name
    intermediate_code

let filename = "rml_toplevel"
let module_name () = String.capitalize filename

let init () =
  Configure.configure ();
  Modules.start_compiling_interface (module_name ());
  Initialization.load_initial_modules ()

let translate_phrase phrase =
  (* Initialization *)
  let module_name = module_name () in
  Location.reset ();

  let err_buf = Buffer.create 256 in
  let err_fmt = Format.formatter_of_buffer err_buf in

  try
    let decl_list = Parse.interactive (Lexing.from_string phrase) in
    (* expend externals *)
    let decl_list = List.map External.expend decl_list in
    (* front-end *)
    let intermediate_code =
      Compiler.compile_implementation_front_end err_fmt None decl_list
    in
    (* the implementation *)
    let ocaml_code =
      Compiler.compile_implementation_back_end_buf err_fmt module_name
        intermediate_code
    in
    None, ocaml_code
  with x ->
    let buf = Buffer.create 256 in
    let fmt = Format.formatter_of_buffer buf in
    let () = Errors.report_error fmt x in
    let () = Format.pp_print_flush fmt () in
    let () = Format.pp_print_flush err_fmt () in
    let err_buf_s = Buffer.contents err_buf in
    let errors = if err_buf_s = "" then
        Buffer.contents buf
      else
        String.concat "\n"
          [ Buffer.contents buf;
            err_buf_s ]
    in
    Some errors, [ phrase ]

(* the main function *)
let compile () =
  let module_name = module_name () in
  let ic = stdin in
  let itf = open_out_bin "/dev/null" in
  let info_fmt = Format.std_formatter in
  let out_chan = stdout in

  (* Initialization *)
  Modules.start_compiling_interface module_name;
  Initialization.load_initial_modules();

  let lexbuf = Lexing.from_channel ic in
  (* Compilation loop *)
  while true do
    begin
      try
	Location.init lexbuf "";
	Lexer.update_loc lexbuf None 1 true 0;
	let decl_list = Parse.interactive lexbuf in
	compile_decl_list module_name (Some itf) info_fmt out_chan decl_list
      with x ->
	Errors.report_error Format.err_formatter x;
	output_string out_chan "let () = ();;\n"
    end;
    flush out_chan;
    Format.pp_print_flush info_fmt ()
  done
