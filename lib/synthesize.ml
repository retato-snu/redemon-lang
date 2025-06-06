open Tree.Syntax
open Texpr
open Abstract

(* list function:
  map, concat, length
  TODO: filter(find)
*)

exception TypeError of string
exception LengthError of string
exception NotFound of string
exception InvalidOperation of string
exception SynthesisConflict of string
exception SynthesisFailed of string

let rec equal_value (v1 : value) (v2 : value) : bool = v1 = v2

let rec show_record (r : record) : string =
  Printf.sprintf "{%s}"
    (String.concat "; "
       (List.map
          (fun (v_id, v) -> Printf.sprintf "%d: %s" v_id (show_value v))
          r))

and show_value (v : value) : string =
  match v with
  | Const c -> Printf.sprintf "Const(%s)" (string_of_const c)
  | Null -> "Null"
  | List l -> Printf.sprintf "List(%d)" (List.length l)
  | Record r -> Printf.sprintf "Record(%s)" (show_record r)
  | Var v_id -> Printf.sprintf "Var(%d)" v_id

let show_var (v : var) : string = string_of_int v

let map (l : value) (f : record -> record) : value =
  match l with
  | List l -> List (List.map f l)
  | _ -> raise (TypeError "Map: Expected a list")

let concat_list (l1 : value) (l2 : value) : value =
  match (l1, l2) with
  | List l1, List l2 -> List (l1 @ l2)
  | _ -> raise (TypeError "Concat: Expected two lists")

let length (l : value) : value =
  match l with
  | List l -> Const (Int (List.length l))
  | _ -> raise (TypeError "Length: Expected a list")

let filter (l : value) (f : record -> bool) : value =
  match l with
  | List l -> List (List.filter f l)
  | _ -> raise (TypeError "Filter: Expected a list")

let find (l : value) (f : record -> bool) : value =
  match l with
  | List l ->
      let rec aux = function
        | [] -> raise (NotFound "Find: Not found")
        | x :: xs -> if f x then Record x else aux xs
      in
      aux l
  | _ -> raise (TypeError "Find: Expected a list")

(* record function *)

let push (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | List l, Record r -> List (r :: l)
  | _ -> raise (TypeError "Push: Expected a list and a record")

let pop (v1 : value) : value =
  match v1 with
  | List [] -> raise (LengthError "Pop: Cannot pop from an empty list")
  | List (r :: l) -> List l
  | _ -> raise (TypeError "Pop: Expected a list")

(* interger function *)

let plus (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | Const (Int i1), Const (Int i2) -> Const (Int (i1 + i2))
  | _ -> raise (TypeError "Plus: Expected two integers")

let minus (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | Const (Int i1), Const (Int i2) -> Const (Int (i1 - i2))
  | _ -> raise (TypeError "Minus: Expected two integers")

let times (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | Const (Int i1), Const (Int i2) -> Const (Int (i1 * i2))
  | _ -> raise (TypeError "Times: Expected two integers")

let divide (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | Const (Int i1), Const (Int i2) ->
      if i2 = 0 then raise (InvalidOperation "divide: divide with 0")
      else Const (Int (i1 / i2))
  | _ -> raise (TypeError "Divide: Expected two integers")

(* string function *)

let change_string_to (v_target_type : value) (s_new_val : string) : value =
  match v_target_type with
  | Const (String _) -> Const (String s_new_val)
  | _ -> raise (TypeError "ChangeStringTo: Expected a string constant")

(* 값을 특정 상수 문자열(구성 요소)로 설정하기 위함 *)
let set_to_const_string (_v_old : value) (v_new_string_const : value) : value =
  match v_new_string_const with
  | Const (String s) -> Const (String s)
  | _ -> raise (TypeError "SetToConstString: Expected a string constant")

let change_string (v1 : value) (s : string) : value =
  match v1 with
  | Const (String _) -> Const (String s)
  | _ -> raise (TypeError "ChangeString: Expected a string constant")

let concat_str (v1 : value) (v2 : value) : value =
  match (v1, v2) with
  | Const (String s1), Const (String s2) -> Const (String (s1 ^ s2))
  | _ -> raise (TypeError "ConcatStr: Expected two string constants")

let lookup_val (v_id : var) (r : record) : value =
  try List.assoc v_id r
  with Not_found ->
    raise (NotFound (Printf.sprintf "Variable %d not found in record" v_id))

type parameterizable_action = P_Click of label | P_Input of label

let show_parameterizable_action (p_act : parameterizable_action) : string =
  match p_act with
  | P_Click l -> Printf.sprintf "Click(%d)" l
  | P_Input l -> Printf.sprintf "Input(%d)" l

let to_param_action (act : action) : parameterizable_action =
  match act with Click l -> P_Click l | Input (l, _) -> P_Input l

type synthesized_function = string * value list

let synthesize (abstraction_data : abstraction) :
    (var * parameterizable_action, synthesized_function) Hashtbl.t =
  let { init; steps_rev } = abstraction_data in
  let steps_chronological = steps_rev in
  (* 시간 순으로 스텝 정렬 *)

  (* 1. 모든 고유 변수 수집 *)
  let all_vars =
    List.sort_uniq compare
      (List.map fst init
      @ List.flatten
          (List.map (fun (_, r) -> List.map fst r) steps_chronological))
  in
  let all_vars = List.sort_uniq compare all_vars in
  (* 중복 제거 및 정렬 *)

  let components = ref [] in
  let add_const_to_components v =
    match v with
    | Const c -> components := Const c :: !components
    | Record r_val -> components := Record r_val :: !components
    | _ -> ()
  in
  List.iter (fun (_, v) -> add_const_to_components v) init;
  (* 초기 상태의 값들 *)
  List.iter
    (fun (_, r) -> List.iter (fun (_, v) -> add_const_to_components v) r)
    steps_chronological;
  (* 모든 스텝의 값들 *)
  let unique_components = List.sort_uniq compare !components in

  (* 중복 제거 및 정렬 *)
  (* Printf.printf "Unique components: %s\n" (String.concat "; " (List.map show_value unique_components)); *)

  (* 3. 관찰 결과 수집: (var_id, p_action, old_val, new_val, actual_action) *)
  (* 키: (var_id * p_action), 값: (old_val, new_val, action) 리스트 *)
  Printf.printf "step 3\n";
  let observations = Hashtbl.create (List.length all_vars * 5) in

  let current_s = ref init in
  (* 현재 상태, 초기 상태로 시작 *)
  List.iter
    (fun (act, next_s) ->
      let prev_s = !current_s in
      let p_act = to_param_action act in
      (* 액션을 매개변수화된 액션으로 변환 *)
      List.iter
        (fun v_id ->
          try
            let old_val = lookup_val v_id prev_s in
            (* 이전 상태에서 변수 값 조회 *)
            let new_val = lookup_val v_id next_s in
            (* 다음 상태에서 변수 값 조회 *)
            if not (equal_value old_val new_val) then
              (* 값이 변경된 경우에만 *)
              let key = (v_id, p_act) in
              let existing_obs =
                try Hashtbl.find observations key with Not_found -> []
              in
              Hashtbl.replace observations key
                ((old_val, new_val, act) :: existing_obs)
            (* 관찰 결과 추가 *)
          with NotFound _ -> () (* 변수가 상태 중 하나에 없거나 추가/제거된 경우 무시 *))
        all_vars;
      current_s := next_s)
    steps_chronological;

  Printf.printf "step 4\n";
  (* 4. 규칙 합성 *)
  let synthesized_rules = Hashtbl.create (Hashtbl.length observations) in

  Hashtbl.iter
    (fun key transitions_rev ->
      let transitions = List.rev transitions_rev in
      (* 
    Printf.printf "Synthesizing for key: (%s, %s) with %d transitions\n"
      (show_var (fst key)) (show_parameterizable_action (snd key)) (List.length transitions);
    List.iter (fun (ov,nv,a) -> Printf.printf "  %s -> %s (action: %s)\n" (show_value ov) (show_value nv) (show_action a)) transitions;
    *)

      let v_id_checking, p_action_checking = key in

      (* 시도할 후보 연산 정의 *)
      (* (연산자 이름, (이전값 -> 새값 -> bool) 검사 함수, [인자 리스트] 옵션) *)
      let candidate_ops :
          (string * (value -> value -> bool) * value list option) list =
        (* 하나의 구성 요소 인자를 받는 연산들 *)
        List.fold_left
          (fun acc comp_arg ->
            ( "plus",
              (fun old new_val ->
                try equal_value (plus old comp_arg) new_val
                with TypeError _ | InvalidOperation _ -> false),
              Some [ comp_arg ] )
            :: ( "minus",
                 (fun old new_val ->
                   try equal_value (minus old comp_arg) new_val
                   with TypeError _ | InvalidOperation _ -> false),
                 Some [ comp_arg ] )
            :: ( "times",
                 (fun old new_val ->
                   try equal_value (times old comp_arg) new_val
                   with TypeError _ | InvalidOperation _ -> false),
                 Some [ comp_arg ] )
            :: ( "divide",
                 (fun old new_val ->
                   try equal_value (divide old comp_arg) new_val
                   with TypeError _ | InvalidOperation _ -> false),
                 Some [ comp_arg ] )
            :: ( "concat_str",
                 (fun old new_val ->
                   try equal_value (concat_str old comp_arg) new_val
                   with TypeError _ -> false),
                 Some [ comp_arg ] )
            :: (* change_string v1 s는 v1이 s가 됨. 즉, new_val = comp_arg *)
               ( "set_to_const_string",
                 (fun _old new_val ->
                   try equal_value (set_to_const_string _old comp_arg) new_val
                   with TypeError _ -> false),
                 Some [ comp_arg ] )
            :: ( "push",
                 (fun old new_val ->
                   try equal_value (push old comp_arg) new_val
                   with TypeError _ | LengthError _ -> false),
                 Some [ comp_arg ] )
            :: acc)
          [] unique_components
        @
        (* 구성 요소 인자를 받지 않는 연산들 *)
        [
          ( "pop",
            (fun old new_val ->
              try equal_value (pop old) new_val
              with TypeError _ | LengthError _ -> false),
            Some [] );
        ]
      in

      let found_rule = ref None in

      (if
         !found_rule = None
         && match p_action_checking with P_Input _ -> true | _ -> false
       then
         let all_match_input_set =
           List.for_all
             (fun (old_val, new_val, actual_act) ->
               match actual_act with
               | Input (_, input_str) -> (
                   (* 실제 Input 액션에서 문자열 가져옴 *)
                   try
                     equal_value new_val (Const (String input_str))
                     (* 새 값이 입력 문자열과 같은지 *)
                     && equal_value
                          (change_string_to old_val input_str)
                          new_val (* 이전 값 타입에 입력 문자열을 설정한 결과가 새 값과 같은지 *)
                   with TypeError _ -> false)
               | _ -> false (* p_action_checking이 P_Input이면 발생하지 않아야 함 *))
             transitions
         in
         if all_match_input_set && transitions <> [] then
           (* Printf.printf "  SUCCESS with set_to_input_string for key (%s, %s)\n" (show_var v_id_checking) (show_parameterizable_action p_action_checking); *)
           found_rule := Some ("set_to_input_string", []));

      (* 다른 후보 연산 시도 *)
      List.iter
        (fun (op_name, op_check, op_args_opt) ->
          if !found_rule = None then
            (* 아직 규칙을 찾지 못한 경우에만 시도 *)
            let all_match_this_op =
              List.for_all
                (fun (old_val, new_val, _actual_act) ->
                  op_check old_val new_val (* 모든 전환에 대해 현재 연산이 성립하는지 확인 *))
                transitions
            in

            if all_match_this_op && transitions <> [] then
              (* 모든 전환에 대해 성립하고, 전환이 비어있지 않으면 *)
              match op_args_opt with
              | Some op_args ->
                  (* 이 연산의 (상수) 인자들 *)
                  (* Printf.printf "  SUCCESS with %s %s for key (%s, %s)\n" op_name (String.concat " " (List.map show_value op_args)) (show_var v_id_checking) (show_parameterizable_action p_action_checking); *)
                  found_rule := Some (op_name, op_args)
              | None ->
                  Printf.printf "  WARNING: op_args_opt was None for %s\n"
                    op_name)
        candidate_ops;

      match !found_rule with
      | Some (fname, fargs) ->
          Hashtbl.add synthesized_rules key (fname, fargs) (* 찾은 규칙 저장 *)
      | None ->
          if transitions <> [] then
            Printf.eprintf
              "Warning: SynthesisFailed for key (%s, %s): No single function \
               explained all %d transitions.\n"
              (show_var v_id_checking)
              (show_parameterizable_action p_action_checking)
              (List.length transitions)
      (* 또는 예외 발생:
        raise (SynthesisFailed (Printf.sprintf "For key (%s, %s), no single function explained all transitions."
          (show_var v_id_checking) (show_parameterizable_action p_action_checking)))
        *))
    observations;

  synthesized_rules

let test () =
  let counter_abstraction =
    {
      sketch = texpr_of_tree (Const (Int 0));
      init = [ (1, Const (Int 0)) ];
      steps_rev =
        [
          (Click 1, [ (1, Const (Int 1)) ]);
          (Click 1, [ (1, Const (Int 2)) ]);
          (Click 2, [ (1, Const (Int 1)) ]);
          (Click 2, [ (1, Const (Int 0)) ]);
        ]
        (* 
       init: {1:0}
       1. Click 1 -> {1:1}  (old:0, new:1) -> plus 1
       2. Click 1 -> {1:2}  (old:1, new:2) -> plus 1
       3. Click 2 -> {1:1}  (old:2, new:1) -> minus 1
       4. Click 2 -> {1:0}  (old:1, new:0) -> minus 1
    *);
    }
  in
  Printf.printf "Synthesizing for Counter Example:\n";
  let rules = synthesize counter_abstraction in
  Hashtbl.iter
    (fun (var_id, p_action) (fname, args) ->
      Printf.printf "Var %s, Action %s: Func: %s, Args: [%s]\n"
        (show_var var_id)
        (show_parameterizable_action p_action)
        fname
        (String.concat ", " (List.map show_value args)))
    rules;
  Printf.printf "\n";

  let string_input_abstraction =
    {
      sketch = texpr_of_tree (Const (String "initial"));
      init = [ (10, Const (String "initial")) ];
      steps_rev =
        [
          (Input (5, "world"), [ (10, Const (String "world")) ]);
          (Click 1, [ (10, Const (String "hello")) ]);
          (Input (5, "changed"), [ (10, Const (String "changed")) ]);
        ]
        (* 
       init: {10:"initial"}
       1. Input(5,"changed") -> {10:"changed"} (old:"initial", new:"changed") -> set_to_input_string
       2. Click 1 -> {10:"hello"} (old:"changed", new:"hello") -> set_to_const_string (Const (String "hello"))
       3. Input(5,"world") -> {10:"world"} (old:"hello", new:"world") -> set_to_input_string
    *);
    }
  in
  Printf.printf "Synthesizing for String Input Example:\n";
  let rules_str = synthesize string_input_abstraction in
  Hashtbl.iter
    (fun (var_id, p_action) (fname, args) ->
      Printf.printf "Var %s, Action %s: Func: %s, Args: [%s]\n"
        (show_var var_id)
        (show_parameterizable_action p_action)
        fname
        (String.concat ", " (List.map show_value args)))
    rules_str;
  Printf.printf "\n";

  let list_push_pop_abstraction =
    {
      sketch = texpr_of_tree (Const (Int 0));
      init = [ (20, List []) ];
      steps_rev =
        [
          (Click 100, [ (20, List []) ]);
          (Click 50, [ (20, List [ [ (1, Const (Int 1)) ] ]) ]);
        ]
        (* 
       init: {20:[]}
       1. Click 50 -> {20:[Record [(1, Const (Int 1))]]} (old:[], new:[R1]) -> push (Record [(1, Const (Int 1))])
       2. Click 100 -> {20:[]} (old:[R1], new:[]) -> pop
    *);
    }
  in
  Printf.printf "Synthesizing for List Push/Pop Example:\n";
  let rules_list = synthesize list_push_pop_abstraction in
  Hashtbl.iter
    (fun (var_id, p_action) (fname, args) ->
      Printf.printf "Var %s, Action %s: Func: %s, Args: [%s]\n"
        (show_var var_id)
        (show_parameterizable_action p_action)
        fname
        (String.concat ", " (List.map show_value args)))
    rules_list
