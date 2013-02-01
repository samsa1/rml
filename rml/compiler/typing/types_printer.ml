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

(* file: types_printer.ml *)

(* Warning: *)
(* This file has been done from CamlLight, Lucid Synchrone and the book *)
(* "Le langage Caml" Pierre Weis Xavier Leroy *)

(* created: 2004-05-25  *)
(* author: Louis Mandel *)

(* $Id$ *)

(* Printing a type expression *)

open Format
open Def_types
open Asttypes
open Misc
open Ident
open Modules
open Global_ident
open Global

(* the long name of an ident is printed *)
(* if it is different from the current module *)
(* or if it is from the standard module *)
let print_qualified_ident q =
  if (compiled_module_name () <> q.qual) &
    (pervasives_module <> q.qual) &
    (!interpreter_module <> q.qual)
  then begin print_string q.qual;print_string "." end;
  print_string (Ident.name q.id)

(* type variables are printed 'a, 'b,... *)
let type_name = new name_assoc_table int_to_alpha
let react_name = new name_assoc_table (fun i -> Format.sprintf "r%i" (i+1))

(** Print reactivity effects **)

(* Find the root of a type, that is the folded version of the type *)
let visited_list, visited = mk_visited ()

type status = NoCycle | Cycle | Rec of reactivity_effect
let max r1 r2 = match r1, r2 with
| Rec _, _ -> r1
| _, Rec _ -> r2
| Cycle, _ | _, Cycle -> Cycle
| NoCycle, NoCycle -> NoCycle

let rec max_list rl =
  List.fold_left max NoCycle rl

let rec find_root check first k =
  if check && k == first then Cycle
  else
    match k.react_desc with
      | React_var | React_pause | React_epsilon -> NoCycle
      | React_seq kl | React_par kl | React_or kl ->
        let rl = List.map (find_root true first) kl in
        max_list rl
      | React_raw (k1, k2) ->
        max (find_root true first k1) (find_root true first k2)
      | React_rec (_, k1) ->
        if visited k then
          NoCycle
        else
          (match find_root true first k1 with
            | NoCycle -> NoCycle
            | Cycle | Rec _ -> Rec k)
      | React_run k -> find_root true first k
      | React_link(link) -> find_root true first link

let find_root k =
  visited_list := [];
  match k.react_desc with
    | React_rec _ -> k
    | _ ->
      match find_root false k k with
        | Rec k1 -> k1
        | Cycle -> assert false
        | NoCycle -> k

let visited_list, visited = mk_visited ()
let rec print_reactivity ff k =
  match k.react_desc with
  | React_link k' -> print_reactivity ff k'
  | React_var ->
      fprintf ff "'%s%s"
        (if k.react_level <> generic then "_" else "")
        (react_name#name k.react_index)
  | React_pause -> fprintf ff "*"
  | React_epsilon -> fprintf ff "0"
  | React_seq l -> fprintf ff "(%a)" (print_reactivity_list "; ") l
  | React_par l -> fprintf ff "(%a)" (print_reactivity_list " || ") l
  | React_or l -> fprintf ff "(%a)" (print_reactivity_list " + ") l
  (* | React_raw (k1, { react_desc = React_var }) -> *)
  (*     fprintf ff "(%a + ..)" *)
  (*       print_reactivity k1 *)
  | React_raw (k1, k2) ->
      fprintf ff "(%a + %a)"
        print_reactivity k1
        print_reactivity k2
  | React_rec (_, k') ->
      if not (visited k) then (
        fprintf ff "(rec '%s. %a)"
          (react_name#name k.react_index)
          print_reactivity k'
      ) else
        fprintf ff "'%s" (react_name#name k.react_index)
  | React_run k' -> fprintf ff "run %a" print_reactivity k'

and print_reactivity_list sep ff l =
  let rec printrec ff l =
    match l with
      [] -> ()
    | [k] ->
	print_reactivity ff k
    | k::rest ->
        fprintf ff "%a%s%a"
	  print_reactivity k
          sep
	  printrec rest in
  printrec ff l

let print_reactivity ff k =
  visited_list := [];
  print_reactivity ff (*(find_root k)*) k


let rec print priority ty =
  open_box 0;
  begin match ty.type_desc with
    Type_var ->
      print_string "'";
      if ty.type_level <> generic then print_string "_";
      print_string (type_name#name ty.type_index)
  | Type_arrow(ty1, ty2) ->
      if priority >= 1 then print_string "(";
      print 1 ty1;
      print_space ();
      print_string "->";
      print_space ();
      print 0 ty2;
      if priority >= 1 then print_string ")"
  | Type_product(ty_list) ->
      if priority >= 2 then print_string "(";
      print_list 2 " * " ty_list;
      if priority >= 2 then print_string ")"
  | Type_constr(name,ty_list) ->
      let n = List.length ty_list in
      if n > 1 then print_string "(";
      print_list 2 ", " ty_list;
      if n > 1 then print_string ")";
      if ty_list <> [] then print_space ();
      print_qualified_ident name.gi
  | Type_link(link) ->
      print priority link
  | Type_process(ty, proc_info) ->
      print 2 ty;
      print_space ();
      print_string "process";
      print_proc_info proc_info
  end;
  close_box ()

and print_proc_info pi =
(*   begin match pi.proc_static with *)
(*   | None | Some(Def_static.Dontknow) -> () *)
(*   | Some(Def_static.Instantaneous) -> print_string "-" *)
(*   | Some(Def_static.Noninstantaneous) -> print_string "+" *)
(*   end *)
  if !Misc.dreactivity then
    printf "[%a]" print_reactivity pi.proc_react

and print_list priority sep l =
  let rec printrec l =
    match l with
      [] -> ()
    | [ty] ->
	print priority ty
    | ty::rest ->
	print priority ty;
	print_string sep;
	printrec rest in
  printrec l

let print ty =
  type_name#reset;
  react_name#reset;
  print 0 ty;
  print_flush ()
let print_scheme { ts_desc = ty } = print ty

let print_value_type_declaration global =
  let prefix = "val" in
  let name = little_name_of_global global in
  open_box 2;
  print_string prefix;
  print_space ();
  if is_an_infix_or_prefix_operator name
  then begin print_string "( "; print_string name; print_string " )" end
  else print_string name;
  print_space ();
  print_string ":";
  print_space ();
  print_scheme (type_of_global global);
  print_string "\n";
  close_box ();
  print_flush ()

(* printing type declarations *)
let print_type_name tc ta =
  let print_one_type_variable i =
    print_string "'";
    print_string (int_to_alpha i) in
  let rec printrec n =
    if n >= ta then ()
    else if n = ta - 1 then print_one_type_variable n
    else begin
      print_one_type_variable n;
      print_string ",";
      printrec (n+1)
    end in
  if ta = 0 then () else if ta = 1
  then
    begin
      print_one_type_variable 0;
      print_space ()
    end
  else begin
    print_string "(";
    printrec 0;
    print_string ")";
    print_space ()
  end;
  print_string (Ident.name tc.id)

(* prints one variant *)
let print_one_variant global =
  print_space ();
  print_string "|";
  open_box 3;
  print_space ();
  print_string (little_name_of_global global);
  (* prints the rest if the arity is not null *)
  begin
    match type_of_constr_arg global with
    | None -> ()
    | Some typ ->
	print_space ();
	print_string "of";
	print_space ();
	print typ
  end;
  close_box ()

(* prints one label *)
let print_one_label global =
  print_space ();
  open_box 2;
  print_string (little_name_of_global global);
  print_string ":";
  print_space ();
  print (type_of_label_res global);
  close_box ()

let rec print_label_list = function
    [] -> ()
  | h::t ->
      print_one_label h;
      if t <> [] then
	begin
	  print_string "; ";
	  print_label_list t
	end

let print_type_declaration gl =
  let q = Global.gi gl in
  let { type_kind = td;
	type_arity = ta; } = Global.info gl in
  open_box 2;
  print_type_name q ta;
  begin match td with
  | Type_abstract -> ()
  | Type_variant global_list ->
      print_string " =";
      open_hvbox 0;
      List.iter print_one_variant global_list;
      close_box ()
  | Type_record global_list ->
      print_string " =";
      print_space ();
      print_string "{";
      open_hvbox 1;
      print_label_list global_list;
      close_box ();
      print_space ();
      print_string "}"
  | Type_rebind te ->
      print_string " =";
      print_space ();
      print te
  end;
  close_box ()

let print_list_of_type_declarations global_list =
  let rec printrec global_list =
    match global_list with
      [] -> ()
    | [global] -> print_type_declaration global
    | global :: global_list ->
	print_type_declaration global;
	print_space ();
	print_string "and ";
	printrec global_list in
  match global_list with
    [] -> ()
  | global_list ->
      open_vbox 0;
      print_string "type ";
      printrec global_list;
      close_box ();
      print_string "\n";;

(* the main printing functions *)
set_max_boxes max_int

let output oc ty =
  set_formatter_out_channel oc;
(*   print_string "  "; *)
  print ty;
  print_flush ()

let output_value_type_declaration oc global_list =
  set_formatter_out_channel oc;
  List.iter print_value_type_declaration global_list

let output_type_declaration oc global_list =
  set_formatter_out_channel oc;
  print_list_of_type_declarations global_list;
  print_flush ()

let output_exception_declaration oc gl =
  set_formatter_out_channel oc;
  open_box 0;
  print_string "exception ";
  print_space ();
  print_string (little_name_of_global gl);
  (* prints the rest if the arity is not null *)
  begin
    match type_of_constr_arg gl with
    | None -> ()
    | Some typ ->
	print_space ();
	print_string "of";
	print_space ();
	print typ
  end;
  close_box ();
  print_string "\n";
  print_flush ()

(* Utils *)
let print_to_string  f x =
  ignore (Format.flush_str_formatter ());
  f Format.str_formatter x;
  Format.fprintf Format.str_formatter "@?";
  Format.flush_str_formatter ()

