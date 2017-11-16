open Core
module Sparse = Owl.Sparse.Matrix.D

module Field = struct
  module T = struct
    type t
      =
      | F0
      | F1
      | F2
      | F3
      | F4
      | F5
      | F6
      | F7
      | F8
      | F9
      | F10
      | F11
      | F12
      | F13
      | F14
      | F15
      | F16
      | F17
      | F18
      | F19
      | Meta0
      | Meta1
      | Meta2
      | Meta3
      | Meta4
      | Meta5
      | Meta6
      | Meta7
      | Meta8
      | Meta9
      | Meta10
      | Meta11
      | Meta12
      | Meta13
      | Meta14
      | Meta15
      | Meta16
      | Meta17
      | Meta18
      | Meta19
      [@@deriving sexp, enumerate, enum, eq, hash]

    let num_fields = max + 1

    let order = Array.init num_fields ~f:ident

    (* compare depends on current order! *)
    let compare (x : t) (y : t) : int =
      (* using Obj.magic instead of to_enum for bettter performance *)
      Int.compare order.(Obj.magic x) order.(Obj.magic y)
  end

  include T
  module Map = Map.Make(T)

  type field = t

  let hash = Hashtbl.hash

  let of_string s =
    t_of_sexp (Sexp.of_string s)

  (** Hack: this way we always know what the abstract fields refer to *)
  let field_to_str_map : string Map.t ref = ref Map.empty

  (** SJS: of_string o to_string may fail *)
  let to_string t =
    match Map.find (!field_to_str_map) t with
    | None -> sprintf "<abstract %s>" @@ Sexp.to_string (sexp_of_t t)
    | Some s -> s

  let is_valid_order (lst : t list) : bool =
    Set.Poly.(equal (of_list lst) (of_list all))

  let set_order (lst : t list) : unit =
    assert (is_valid_order lst);
    List.iteri lst ~f:(fun i fld -> order.(to_enum fld) <- i)

  (* Not a clean way to invert a permutation, but fast *)
  let invert arr =
    let inverted = Array.init num_fields ~f:ident in
    Array.iteri arr ~f:(fun i elt -> inverted.(elt) <- i );
    inverted

  let get_order () =
    Array.to_list (invert order)
    |> List.filter_map ~f:of_enum

  module type ENV = sig
    type t
    val empty : t
    exception Full
    val add : t -> string -> field Syntax.meta_init -> bool -> t (* may raise Full *)
    val lookup : t -> string -> field * (field Syntax.meta_init * bool) (* may raise Not_found *)
  end

  module Env : ENV = struct

    type t = {
      alist : (string * (field * (field Syntax.meta_init * bool))) list;
      depth : int
    }

    let empty = { alist = []; depth = 0 }

    exception Full

    let add env name init mut =
      let field =
        match env.depth with
        | 0 -> Meta0
        | 1 -> Meta1
        | 2 -> Meta2
        | 3 -> Meta3
        | 4 -> Meta4
        | 5 -> Meta5
        | 6 -> Meta6
        | 7 -> Meta7
        | 8 -> Meta8
        | 9 -> Meta9
        | 10 -> Meta10
        | 11 -> Meta11
        | 12 -> Meta12
        | 13 -> Meta13
        | 14 -> Meta14
        | 15 -> Meta15
        | 16 -> Meta16
        | 17 -> Meta17
        | 18 -> Meta18
        | 19 -> Meta19
        | _ -> raise Full
      in
      { alist = List.Assoc.add ~equal:(=) env.alist name (field, (init, mut));
        depth = env.depth + 1}

    let lookup env name =
      List.Assoc.find_exn ~equal:(=) env.alist name
  end
(*
  (* Heuristic to pick a variable order that operates by scoring the fields
     in a policy. A field receives a high score if, when a test field=X
     is false, the policy can be shrunk substantially.

     NOTE(arjun): This could be done better, but it seems to work quite well
     on FatTrees and the SDX benchmarks. Some ideas for improvement:

     - Easy: also account for setting tests field=X suceeded
     - Harder, but possibly much better: properly calculate the size of the
       pol for different field assignments. Don't traverse the policy
       repeatedly. Instead, write a size function that returns map from
       field assignments to sizes. *)
  let auto_order (pol : Syntax.policy) : unit =
    let open Syntax in
    (* Construct array of scores, where score starts at 0 for every field *)
    let count_arr = Array.init num_fields ~f:(fun _ -> 0) in
    let rec f_pred size (env, pred) = match pred with
      | True -> ()
      | False -> ()
      | Test (Syntax.Meta (id,_)) ->
        begin match Env.lookup env id with
        | (f, (Alias hv, false)) ->
          let f = to_enum f in
          let f' = to_enum (of_hv hv) in
          count_arr.(f) <- count_arr.(f) + size;
          count_arr.(f') <- count_arr.(f') + size
        | (f,_) ->
          let f = to_enum f in
          count_arr.(f) <- count_arr.(f) + size
        end
      | Test hv ->
        let f = to_enum (of_hv hv) in
        count_arr.(f) <- count_arr.(f) + size
      | Or (a, b) -> f_pred size (env, a); f_pred size (env, b)
      | And (a, b) -> f_pred size (env, a); f_pred size (env, b)
      | Neg a -> f_pred size (env, a) in
    let rec f_seq' pol lst env k = match pol with
      | Mod _ -> k (1, lst)
      | Filter a -> k (1, (env, a) :: lst)
      | Seq (p, q) ->
        f_seq' p lst env (fun (m, lst) ->
          f_seq' q lst env (fun (n, lst) ->
            k (m * n, lst)))
      | Union _ -> k (f_union pol env, lst)
      | Let { id; init; mut; body=p } ->
        let env = Env.add env id init mut in
        f_seq' p lst env k
      | Star p -> k (f_union p env, lst)
      | Link (sw,pt,_,_) -> k (1, (env, Test (Switch sw)) :: (env, Test (Location (Physical pt))) :: lst)
      | VLink (sw,pt,_,_) -> k (1, (env, Test (VSwitch sw)) :: (env, Test (VPort pt)) :: lst)
      | Dup -> k (1, lst)
    and f_seq pol env : int =
      let (size, preds) = f_seq' pol [] env (fun x -> x) in
      List.iter preds ~f:(f_pred size);
      size
    and f_union' pol lst env k = match pol with
      | Mod _ -> (1, lst)
      | Filter a -> (1, (env, a) :: lst)
      | Union (p, q) ->
        f_union' p lst env (fun (m, lst) ->
          f_union' q lst env (fun (n, lst) ->
            k (m + n, lst)))
      | Seq _ -> k (f_seq pol env, lst)
      | Let { id; init; mut; body=p } ->
        let env = Env.add env id init mut in
        k (f_seq p env, lst)
      | Star p -> f_union' p lst env k
      | Link (sw,pt,_,_) -> k (1, (env, Test (Switch sw)) :: (env, Test (Location (Physical pt))) :: lst)
      | VLink (sw,pt,_,_) -> k (1, (env, Test (VSwitch sw)) :: (env, Test (VPort pt)) :: lst)
      | Dup -> k (1, lst)
    and f_union pol env : int =
      let (size, preds) = f_union' pol [] env (fun x -> x) in
      List.iter preds ~f:(f_pred size);
      size
    in
    let _ = f_seq pol Env.empty in
    Array.foldi count_arr ~init:[] ~f:(fun i acc n -> ((Obj.magic i, n) :: acc))
    |> List.stable_sort ~cmp:(fun (_, x) (_, y) -> Int.compare x y)
    |> List.rev (* SJS: do NOT remove & reverse order! Want stable sort *)
    |> List.map ~f:fst
    |> set_order *)

end

module Value = struct
  include Int
  let subset_eq = equal
end



module PreAction = struct
  module T = Field.Map
  open T

  type t = Value.t Field.Map.t [@@deriving sexp, eq]

  let compare = compare_direct Value.compare
  let one = empty
  let hash_fold_t = Map.hash_fold_direct Field.hash_fold_t Value.hash_fold_t

  let prod x y =
    (* Favor modifications to the right *)
    merge x y ~f:(fun ~key m ->
      match m with | `Both(_, v) | `Left v | `Right v -> Some(v))

  let to_hvs = to_alist ~key_order:`Increasing

  let to_string (t : t) : string =
    if T.is_empty t then "skip" else
    to_alist t
    |> List.map ~f:(fun (f,v) ->
        sprintf "%s := %s" (Field.to_string f) (Value.to_string v))
    |> String.concat ~sep:", "
    |> sprintf "[%s]"
end

module Action = struct
  type t =
  | Drop
  | Action of PreAction.t
  [@@deriving sexp, compare, hash, eq]

  let zero = Drop
  let one = Action PreAction.one

  let prod x y =
    match x,y with
    | Drop, _
    | _, Drop -> Drop
    | Action a1, Action a2 -> Action (PreAction.prod a1 a2)

  let sum x y = failwith "multicast not implemented!"

  let to_hvs t = match t with
    | Drop -> None
    | Action a -> Some (PreAction.to_hvs a)

  let to_string (t : t) : string =
    match t with
    | Drop -> "drop"
    | Action a -> PreAction.to_string a
end



module ActionDist = struct

  module T = Dist.Make(Action)
  include T

  let zero = dirac Action.zero
  let is_zero = T.equal zero

  let one = T.dirac Action.one
  let is_one = T.equal one

  let prod x y =
    if is_zero x || is_zero y then
      zero
    else if is_one x then
      y
    else if is_one y then
      x
    else
      T.prod_with ~f:Action.prod x y

  let negate t : t =
    (* This implements negation for the [zero] and [one] actions. Any
       non-[zero] action will be mapped to [zero] by this function. *)
    if is_zero t then one else zero

  let to_string t =
    to_alist t
    |> List.map ~f:(fun (act, prob) -> sprintf "%s @ %s"
                    (Action.to_string act)
                    (Prob.to_float prob |> Float.to_string_round_trippable))
    |> String.concat ~sep:"; "
    |> sprintf "{ %s }"

  (* sum = ampersand (and ampersand only!). It should ever only be used to
     implement disjunction. Thus, we must have x,y \in {0,1}  *)
  let sum x y =
    if is_zero x then y else
    if is_zero y then x else
    if is_one x && is_one y then x else
      failwith (sprintf "multicast not implemented! cannot add (in the sense of &) %s and %s"
        (to_string x) (to_string y)
      )
end


(** symbolic packets *)
module PrePacket = struct
  type nomval =
    | Const of Value.t
    | Atom (** An atom in the sense of nominal sets. Some fixed that value that is different
               from all constants. To a first approximation, a sort of wildcard, but it ranges
               only over values that do not appear as constants.
            *)
    [@@deriving compare, eq, sexp]

  type t = nomval Field.Map.t [@@deriving compare, eq, sexp]
  (** Symbolic packet. Represents a set of concrete packets { π }.

      f |-> Const v  means π.f = v
      f |-> Atom     means π.f \in { values not appearing as f-values }
      f |-> ⊥        means π.f can have any value

      In particular, the empty map represents the set of all packets, and a map
      that associates a constant with every field represents a singleton set.
  *)

  let empty = Field.Map.empty

  let modify (pk : t) (f : Field.t) (v : nomval) : t =
    Map.add pk ~key:f ~data:v

  let apply (pk : t) (action : PreAction.t) : t =
    Field.Map.merge pk action ~f:(fun ~key:_ -> function
      | `Left v -> Some v
      | `Right v | `Both (_,v) -> Some (Const v))

  let to_preaction pk =
    Map.filter_map pk ~f:(function
      | Const v -> Some v
      | Atom -> None)

  let pp fmt (pk:t) : unit =
    Format.fprintf fmt "@[";
    if Map.is_empty pk then Format.fprintf fmt "*@ " else
    Map.iteri pk ~f:(fun ~key ~data -> Format.fprintf fmt "@[%s=%s@]@ "
      (Field.to_string key)
      begin match data with
      | Atom -> "*"
      | Const v -> Int.to_string v
      end);
    Format.fprintf fmt "@]"

  let to_string pk : string =
    Format.asprintf "%a" pp pk
end

(** "packet" is a bad name and used just for historicaly reasons. It's a symbolic
    encoding of a packet set (possibly the empty set).
*)
module Packet = struct
  type t =
    | Emptyset
    | Pk of PrePacket.t
    [@@deriving compare, eq, sexp]

  let modify (pk : t) (f : Field.t) (v : PrePacket.nomval) : t =
    match pk with
    | Emptyset -> Emptyset
    | Pk pk -> Pk (PrePacket.modify pk f v)

  let apply (pk : t) (act : Action.t) : t =
    match pk, act with
    | Emptyset, _
    | _, Drop ->
      Emptyset
    | Pk pk, Action act ->
      Pk (PrePacket.apply pk act)

  let to_action pk =
    match pk with
    | Emptyset -> Action.Drop
    | Pk pk -> Action.Action (PrePacket.to_preaction pk)

  let pp fmt (pk:t) : unit =
    match pk with
    | Emptyset -> Format.fprintf fmt "@[∅]"
    | Pk pk -> PrePacket.pp fmt pk

  let to_string pk : string =
    Format.asprintf "%a" pp pk
end



module Fdd00 = Vlr.Make(Field)(Value)(ActionDist)



(** domain of an Fdd *)
module Domain = struct
  module Valset = Set.Make(struct type t = PrePacket.nomval [@@deriving sexp, compare] end)
  type t = Valset.t Field.Map.t


  let merge d1 d2 : t =
    Map.merge d1 d2 ~f:(fun ~key -> function
      | `Left s | `Right s -> Some s
      | `Both (l,r) -> Some (Set.union l r))

  let of_fdd (fdd : Fdd00.t) : t =
    let rec for_fdd dom fdd =
      match Fdd00.unget fdd with
      | Leaf r ->
        for_leaf dom r
      | Branch ((field,_),_,_) ->
        let (vs, residuals, all_false) = for_field field fdd [] [] in
        let vs =
          List.map vs ~f:(fun v -> PrePacket.Const v)
          |> Valset.of_list
        in
        let dom = Map.update dom field ~f:(function
          | None -> vs
          | Some vs' -> Set.union vs vs')
        in
        List.fold residuals ~init:dom ~f:for_fdd

    (** returns list of values appearing in tests with field [f] in [fdd], and
        residual trees below f-tests, and the all-false branch with respect to
        field f. *)
    and for_field f fdd vs residual =
      match Fdd00.unget fdd with
      | Branch ((f',v), tru, fls) when f' = f ->
        for_field f fls (v::vs) (tru::residual)
      | Branch _ | Leaf _ ->
        (vs, fdd::residual, fdd)

    and for_leaf dom dist =
      ActionDist.support dist
      |> List.fold ~init:dom ~f:for_action

    and for_action dom action =
      match action with
      | Drop -> dom
      | Action action -> for_preaction dom action

    and for_preaction dom action =
      PreAction.T.to_alist action
      |> Util.map_snd ~f:(fun v -> Valset.singleton (Const v))
      |> Field.Map.of_alist_exn
      |> merge dom

    in
    for_fdd Field.Map.empty fdd
    (* SJS: this is a sound overapproximation, but a very expensive one!! *)
    |> Field.Map.map ~f:(fun vs -> Set.add vs PrePacket.Atom)

  let size (dom : t) : int =
    (* SJS: +1 for the empty set! *)
    Map.fold dom ~init:1 ~f:(fun ~key ~data:vs acc -> acc * (Valset.length vs))
    + 1

  let pre_variants (dom : t) : PrePacket.t list =
    Map.fold dom ~init:[PrePacket.empty] ~f:(fun ~key:f ~data:vs pks ->
      Valset.to_list vs
      |> List.concat_map ~f:(fun v -> List.map pks ~f:(fun pk ->
        PrePacket.modify pk f v))
    )

  let variants (dom : t) : Packet.t list =
    pre_variants dom
    |> List.map ~f:(fun pk -> Packet.Pk pk)
    |> List.cons (Packet.Emptyset)

  let pp fmt (dom:t) : unit =
    Format.fprintf fmt "@[";
    if Map.is_empty dom then Format.fprintf fmt "*@ " else
    Map.iteri dom ~f:(fun ~key ~data -> Format.fprintf fmt "@[%s=%s@]@ "
      (Field.to_string key)
      begin
        Set.to_list data
        |> List.to_string ~f:(function
          | PrePacket.Atom -> "*"
          | PrePacket.Const v -> Int.to_string v)
      end
    );
    Format.fprintf fmt "@]"

  let to_string dom : string =
    Format.asprintf "%a" pp dom

end





(** packet coding *)
type 'domain_witness hyperpoint = int list
type 'domain_witness codepoint = int
type 'domain_witness index = { i : int }  [@@unboxed]
type 'domain_witness index0 = { i : int } [@@unboxed]

module type DOM = sig
  val domain : Domain.t
end

module type CODING = sig
  type domain_witness
  val dom : Domain.t
  val print : unit -> unit

  (** Encoding of packet in n dimensional space.
      More precisely, a packet is encoded as a point in a hypercube, with the
      coordinates being of type int.
      If [dimension] = {k1, ..., kn}, then the hypercube is given by
        {0, ..., k1} x ... x {0, ..., kn}.
      The points within this cube are represented as lists, rather than tuples,
      because n is not known at compile time.
  *)
  module rec Hyperpoint : sig
    type t = domain_witness hyperpoint
    val dimension : int list
    val to_codepoint : t -> Codepoint.t
    (* codepoints can represent the empty set, but hyperpoints cannot *)
    val of_codepoint : Codepoint.t -> t option
    val to_pre_pk : t -> PrePacket.t
    val of_pre_pk : PrePacket.t -> t
  end

  (** Encoding of packets as integers >= 0, i.e. points in single dimensional space. *)
  and Codepoint : sig
    type t = domain_witness codepoint
    val max : t
    val emptyset : t
    (* option, because the empty set is not a hyperpoint *)
    val to_hyperpoint : t -> Hyperpoint.t option
    val of_hyperpoint : Hyperpoint.t -> t
    val to_pk : t -> Packet.t
    val of_pk : Packet.t -> t
    val to_index : t -> Index.t
    val of_index : Index.t -> t
    val to_index0 : t -> Index0.t
    val of_index0 : Index0.t -> t
  end

  (** Encoding of packets as strictly positive integers, i.e. 1-based matrix indices. *)
  and Index : sig
    type t = domain_witness index
    val max : t
    val emptyset : t
    val of_pk : Packet.t -> t
    val to_pk : t -> Packet.t
    (* val test : Field.t -> PrePacket.nomval -> t -> bool *)
    val modify : Field.t -> PrePacket.nomval -> t -> t
    (* val test' : Field.t -> PrePacket.nomval -> int -> bool *)
    val modify' : Field.t -> PrePacket.nomval -> int -> int
    val pp : Format.formatter -> t -> unit
    val pp' : Format.formatter -> int -> unit
  end

  (** Encoding of packets as positive integers (including 0), i.e. 0-based matrix indices. *)
  and Index0 : sig
    type t = domain_witness index0
    val max : t
    val emptyset : t
    val of_pk : Packet.t -> t
    val to_pk : t -> Packet.t
    (* val test : Field.t -> PrePacket.nomval -> t -> bool *)
    val modify : Field.t -> PrePacket.nomval -> t -> t
    (* val test' : Field.t -> PrePacket.nomval -> int -> bool *)
    val modify' : Field.t -> PrePacket.nomval -> int -> int
    val pp : Format.formatter -> t -> unit
    val pp' : Format.formatter -> int -> unit
  end
end

module Coding(D : DOM) : CODING = struct

  let dom : Domain.t = D.domain
  let domain : (Field.t * PrePacket.nomval list) list =
    Map.to_alist (Map.map D.domain ~f:Set.to_list)

  type domain_witness

  module Hyperpoint = struct
    type t = domain_witness hyperpoint

    let dimension =
      List.map domain ~f:(fun (_,vs) -> List.length vs)

    let injection : (Field.t * (PrePacket.nomval -> int)) list =
      List.Assoc.map domain ~f:(fun vs ->
        List.mapi vs ~f:(fun i v -> (v, i))
        |> Map.Poly.of_alist_exn
        |> Map.Poly.find_exn)

    let ejection : (Field.t * (int -> PrePacket.nomval)) list =
      List.Assoc.map domain ~f:List.to_array
      |> List.Assoc.map ~f:(fun inj v -> inj.(v))


    let to_codepoint t =
      (* SJS: +1 for empty set *)
      1 + List.fold2_exn t dimension ~init:0 ~f:(fun cp v n -> v + n * cp)

    let of_codepoint cp =
      (* SJS: 0 = empty set *)
      if cp = 0 then None else
      List.fold_right dimension ~init:(cp-1,[]) ~f:(fun n (cp, hp) ->
        let (cp, v) = Int.(cp /% n, cp % n) in
        (cp, v::hp))
      |> snd
      |> Option.some

    let to_pre_pk t =
      List.fold2_exn t ejection ~init:Field.Map.empty ~f:(fun pk v (f, veject) ->
        Field.Map.add pk ~key:f ~data:(veject v))

    let of_pre_pk pk =
      List.map injection ~f:(fun (f, vinj) -> vinj (Field.Map.find_exn pk f))

  end

  module Codepoint = struct
    type t = domain_witness codepoint
    let emptyset = 0
    let to_hyperpoint = Hyperpoint.of_codepoint
    let of_hyperpoint = Hyperpoint.to_codepoint
    let to_pre_pk cp = Option.(to_hyperpoint cp >>| Hyperpoint.to_pre_pk)
    let of_pre_pk = Fn.compose of_hyperpoint Hyperpoint.of_pre_pk
    let to_pk cp = if cp = emptyset then Packet.Emptyset else
      Packet.Pk (Option.value_exn (to_pre_pk cp))
    let of_pk pk = match pk with
      | Packet.Emptyset -> emptyset
      | Packet.Pk pk -> of_pre_pk pk
    let max = List.fold ~init:1 ~f:( * ) Hyperpoint.dimension
    let to_index cp : domain_witness index = { i = cp + 1  }
    let of_index (idx : domain_witness index) = idx.i - 1
    let to_index0 cp : domain_witness index0 = { i = cp }
    let of_index0 (idx : domain_witness index0) = idx.i
  end

  module Index = struct
    type t = domain_witness index
    let of_pk = Fn.compose Codepoint.to_index Codepoint.of_pk
    let to_pk = Fn.compose Codepoint.to_pk Codepoint.of_index
    let max = Codepoint.(to_index max)
    let emptyset = Codepoint.(to_index emptyset)
    (* let test f n t = Packet.test f n (to_pk t) *)
    let modify f n t = of_pk (Packet.modify (to_pk t) f n)
    (* let test' f n i = test f n { i = i } *)
    let modify' f n i = (modify f n { i = i }).i
    let pp fmt t = Packet.pp fmt (to_pk t)
    let pp' fmt i = Packet.pp fmt (to_pk { i = i })
  end

  module Index0 = struct
    type t = domain_witness index0
    let of_pk = Fn.compose Codepoint.to_index0 Codepoint.of_pk
    let to_pk = Fn.compose Codepoint.to_pk Codepoint.of_index0
    let max = Codepoint.(to_index0 max)
    let emptyset = Codepoint.(to_index0 emptyset)
    (* let test f n t = Packet.test f n (to_pk t) *)
    let modify f n t = of_pk (Packet.modify (to_pk t) f n)
    (* let test' f n i = test f n { i = i } *)
    let modify' f n i = (modify f n { i = i }).i
    let pp fmt t = Packet.pp fmt (to_pk t)
    let pp' fmt i = Packet.pp fmt (to_pk { i = i })
  end

  let print () = begin
    let fmt = Format.std_formatter in
    let fprintf = Format.fprintf in
    let n = Domain.size dom in
    fprintf fmt "domain size = %d\n" n;
    if n < 50 then begin
      fprintf fmt "index packet mapping:\n%!";
      Array.init n ~f:ident
      |> Array.iter ~f:(fun i -> fprintf fmt " %d = %a\n%!" i Index0.pp' i);
      fprintf fmt "\n%!";
    end
  end

end




module Fdd0 = struct
  include Fdd00

  let iter_maplets fdd ~dom ~(f : (Domain.t * Action.t * Prob.t) -> unit) : unit =
    let rec of_node fdd dom =
      match unget fdd with
      | Leaf r ->
        of_leaf r dom
      | Branch ((f,v), tru, fls) ->
        let v = PrePacket.Const v in
        let tru_dom = Map.add dom ~key:f ~data:Domain.Valset.(singleton v) in
        let fls_dom = Map.update dom f ~f:(function
          | None -> assert false
          | Some vs -> Set.remove vs v)
        in
        of_node tru tru_dom;
        of_node fls fls_dom
    and of_leaf dist dom =
      ActionDist.to_alist dist
      |> List.iter ~f:(fun (act, prob) -> f (dom, act, prob))
    in
    of_node fdd dom
end




(** matrix representation of Fdd0 *)
module Matrix = struct
  type t = {
    matrix : Sparse.mat;
    coding : (module CODING);
    dom : Domain.t;
  }

  let pre_packet_variants (pk : PrePacket.t) (dom : Domain.t) : PrePacket.t list =
    Field.Map.fold2 pk dom ~init:[pk] ~f:(fun ~key:f ~data pks ->
      match data with
      | `Both _ -> pks
      | `Left _ -> assert false
      | `Right vs -> List.concat_map pks ~f:(fun pk ->
          Set.to_list vs
          |> List.map ~f:(fun v -> Field.Map.add pk ~key:f ~data:v)
        )
    )

  let packet_variants (pk : Packet.t) (dom : Domain.t) : Packet.t list =
    match pk with
    | Emptyset -> [pk]
    | Packet.Pk pk ->
      pre_packet_variants pk dom
      |> List.map ~f:(fun pk -> Packet.Pk pk)

  let maplet_to_matrix_entries (coding : (module CODING)) (dom, act, prob)
    : (int * int * Prob.t) list =
    let module Conv = (val coding : CODING) in
    Domain.pre_variants dom
    |> List.map ~f:(fun pk ->
      let pk = Packet.Pk pk in
      let pk' = Packet.apply pk act in
      ((Conv.Index0.of_pk pk).i, (Conv.Index0.of_pk pk').i, prob)
    )

  let iter_fdd_entries fdd (coding : (module CODING)) ~f =
    let module Coding = (val coding : CODING) in
    let dom = Coding.dom in
    Fdd0.iter_maplets fdd ~dom ~f:(fun maplet ->
      maplet_to_matrix_entries coding maplet
      |> List.iter ~f
    )


  let get_pk_action t (pk : PrePacket.t) : ActionDist.t =
    let module Coding = (val t.coding : CODING) in
    let row_to_action row : ActionDist.t =
      Sparse.foldi_nz (fun _i j dist prob ->
          Coding.Index0.to_pk { i = j }
          |> Packet.to_action
          |> ActionDist.unsafe_add dist (Prob.of_float prob)
        )
        ActionDist.empty
        row
      |> ActionDist.unsafe_normalize
    in
    let total_pk_action pk : ActionDist.t =
      let i = (Coding.Index0.of_pk (Packet.Pk pk)).i in
      let rowi = Sparse.row t.matrix i in
      row_to_action rowi
    in
    (* FIXME: inefficient solution for now for safety! *)
    pre_packet_variants pk t.dom
    |> List.map ~f:total_pk_action
    |> List.group ~break:(fun x y -> not (ActionDist.equal x y))
    |> function
      | [act::_] -> act
      | ((act::_)::_) as actions->
        eprintf "!!! WARNING: possibly unsounds matix -> Fdd conversion\n%!";
        List.concat actions
        |> List.iter ~f:(fun dist -> eprintf "  %s\n" (ActionDist.to_string dist));
        act
      | _ -> assert false

end



module Fdd = struct

  include Fdd0
  open Syntax

  (** SJS: keep global string |-> Field.t map so that we can compare policies
      that are compiled to Fdds one after another
  *)
  let field_allocation_tbl : (string, Field.t) Hashtbl.t = String.Table.create ()
  let next_field = ref 0

  (* sound, but could be better *)
  let clear_cache ~(preserve:Int.Set.t) : unit =
    clear_cache ~preserve;
    if Set.is_empty preserve then (
      Hashtbl.clear field_allocation_tbl;
      next_field := 0;
      Field.field_to_str_map := Field.Map.empty
    );
    ()

  let allocate_fields (pol : string policy) : Field.t policy =
    let do_field env (f : string) : Field.t =
      match Field.Env.lookup env f with
      | (field, _) -> field
      | exception Not_found ->
        String.Table.find_or_add field_allocation_tbl f ~default:(fun () ->
          let open Field in
          let field = match !next_field with
            | 0 -> F0
            | 1 -> F1
            | 2 -> F2
            | 3 -> F3
            | 4 -> F4
            | 5 -> F5
            | 6 -> F6
            | 7 -> F7
            | 8 -> F8
            | 9 -> F9
            | 10 -> F10
            | 11 -> F11
            | 12 -> F12
            | 13 -> F13
            | 14 -> F14
            | 15 -> F15
            | 16 -> F16
            | 17 -> F17
            | 18 -> F18
            | 19 -> F19
            | _ -> failwith "too many fields! (may need to clear the cache?)"
          in incr next_field; field)
    in
    let rec do_pol env (p : string policy) : Field.t policy =
      match p with
      | Filter pred ->
        Filter (do_pred env pred)
      | Modify (f,v) ->
        Modify (do_field env f, v)
      | Seq (p, q) ->
        Seq (do_pol env p, do_pol env q)
      | Ite (a, p, q) ->
        Ite (do_pred env a, do_pol env p, do_pol env q)
      | While (a, p) ->
        While (do_pred env a, do_pol env p)
      | Choice dist ->
        Choice (Util.map_fst dist ~f:(do_pol env))
      | Let { id; init; mut; body; } ->
        let init = match init with
          | Alias f -> Alias (do_field env f)
          | Const v -> Const v
        in
        let env = Field.Env.add env id init mut in
        let (id,_) = Field.Env.lookup env id in
        let body = do_pol env body in
        Let { id; init; mut; body; }
    and do_pred env (p : string pred) : Field.t pred =
      match p with
      | True -> True
      | False -> False
      | Test (f, v) -> Test (do_field env f, v)
      | And (p, q) -> And (do_pred env p, do_pred env q)
      | Or (p, q) -> Or (do_pred env p, do_pred env q)
      | Neg p -> Neg (do_pred env p)
    in
    let pol = do_pol Field.Env.empty pol in
    let field_map =
      String.Table.to_alist field_allocation_tbl
      |> List.map ~f:(fun (str, field) -> (field, str))
      |> Field.Map.of_alist_exn
    in
    Field.field_to_str_map := field_map;
    pol

  let of_test hv =
    atom hv ActionDist.one ActionDist.zero

  let of_mod (f,v) =
    const (ActionDist.dirac (Action.Action (PreAction.T.singleton f v)))

  let negate fdd =
    map_r fdd ~f:ActionDist.negate

  let rec of_pred p =
    match p with
    | True      -> id
    | False     -> drop
    | Test(hv)  -> of_test hv
    | And(p, q) -> prod (of_pred p) (of_pred q)
    | Or (p, q) -> sum (of_pred p) (of_pred q)
    | Neg(q)    -> negate (of_pred q)


  (* SJS: copied and adopted apply algorithm from Vlr.ml *)
  let convex_sum t1 prob t2 : t =
    (* the function to apply at the leaves *)
    let f x y = ActionDist.convex_sum x prob y in
    let cache : (t*t, t) Hashtbl.t = BinTbl.create ~size:1000 () in
    let rec sum x y =
      BinTbl.find_or_add cache (x, y) ~default:(fun () -> sum' x y)
    and sum' x y =
      match unget x, unget y with
      | Leaf x, _      ->
        map_r (fun y -> f x y) y
      | _     , Leaf y ->
        map_r (fun x -> f x y) x
      | Branch((vx, lx), tx, fx), Branch((vy, ly), ty, fy) ->
        begin match Field.compare vx vy with
        |  0 ->
          begin match Value.compare lx ly with
          |  0 -> unchecked_cond (vx,lx) (sum tx ty) (sum fx fy)
          | -1 -> unchecked_cond (vx,lx) (sum tx (restrict [(vx, lx)] y)) (sum fx y)
          |  1 -> unchecked_cond (vy,ly) (sum (restrict [(vy, ly)] x) ty) (sum x fy)
          |  _ -> assert false
          end
        | -1 -> unchecked_cond (vx,lx) (sum tx y) (sum fx y)
        |  1 -> unchecked_cond (vy,ly) (sum x ty) (sum x fy)
        |  _ -> assert false
        end
    in
    sum t1 t2

  let n_ary_convex_sum ts : t =
    let (ts, probs) = List.unzip ts in
    let probs = Util.n_ary_to_binary_right_associative_probs probs in
    (* To implement an n-ary convex sum, we only need n-1 binary convex sums.
       Hence, we expose of the right-most probability. Moreover, we reverse
       the list of Fdds, because the binary sums are associated to the right.
     *)
    match List.rev ts, List.rev probs with
    | t::ts, _::probs ->
      List.zip_exn ts probs
      (* because we are doing a fold_left over the reversed list, the accumulator
         is the right-hand fdd, and the current fdd goes on the left. *)
      |> List.fold_left ~init:t ~f:(fun tr (tl, p) -> convex_sum tl p tr)
    | _ ->
      failwith "0-ary convex sum is undefined!"


  let seq_tbl = BinTbl.create ~size:1000 ()

  let clear_cache ~preserve = begin
    BinTbl.clear seq_tbl;
    clear_cache preserve;
  end

  let seq t u =
    match unget u with
    | Leaf _ -> prod t u (* This is an optimization. If [u] is an
                            [Action.Par.t], then it will compose with [t]
                            regardless of however [t] modifies packets. None
                            of the decision variables in [u] need to be
                            removed because there are none. *)
    | Branch _ ->
      dp_map t
        ~f:(fun dist ->
          ActionDist.to_alist dist
          |> Util.map_fst ~f:(fun action ->
            match action with
            | Action.Drop -> drop
            | Action.Action preact ->
              restrict (PreAction.to_hvs preact) u
              |> prod (const @@ ActionDist.dirac action)
          )
          |> n_ary_convex_sum
        )
        ~g:(fun v t f -> cond v t f)
        ~find_or_add:(fun t -> BinTbl.find_or_add seq_tbl (t,u))

  (* SJS: the fragment of ProbNetKAT we are using does not have a union operator!
     We only have boolean disjunction and disjoint union.
   *)
  (* let union t u = sum t u *)

  (* FIXME: this skeleton is very large, so this may become a bottleneck.
     I used to use a smaller skeleton computed from ap and not_a, but I am not
     sure this was sound. Reconsider should this become a bottleneck in the
     future. *)
  let mk_skeleton dom =
    Field.Map.fold dom ~init:id ~f:(fun ~key:field ~data:vs init ->
      Set.fold vs ~init ~f:(fun init v ->
        match v with
        | PrePacket.Atom -> init
        | PrePacket.Const v -> cond (field,v) init (negate init)
      )
    )

  let of_mat (matrix : Matrix.t) : t =
    let skeleton = mk_skeleton Matrix.(matrix.dom) in
    let rec do_node skeleton pk =
      match unget skeleton with
      | Leaf r ->
        const (Matrix.get_pk_action matrix pk)
      | Branch ((f,v), tru, fls) ->
        let tru = do_node tru PrePacket.(modify pk f (Const v)) in
        let fls = do_node fls PrePacket.(modify pk f Atom) in
        unchecked_cond (f,v) tru fls
    in
    do_node skeleton PrePacket.empty

  let fixpoint_race ap not_a ~child =
    let open Caml.Unix in
    let rec loop p =
      (* printf "[ocaml] naive fixed-point, n = %d\n%!" n; *)
      match waitpid [WNOHANG] child with
      | 0,_ ->
        (* child process still working; do another iteration *)
        let p2 = seq p p in
        if equal p p2 then Some p else loop p2
      | pid, WEXITED 0 when pid = child ->
        (* child processs finished succesfully; stop naive fixpoint and wait for python reply *)
        None
      | pid, _ when pid = child ->
        failwith "OCaml child process exited abnormally"
      | _ ->
        assert false
    in
    Util.timed "fixpoint race" (fun () -> loop (sum ap not_a))


  let python_iterate ap not_a (coding : (module CODING)) to_py =
    let module Coding = (val coding : CODING) in
    let n = Domain.size Coding.dom in

    let send_matrix_entry (i,j,p) : unit =
      Prob.to_float p
      |> Float.to_string_round_trippable
      |> Out_channel.fprintf to_py "%d %d %s\n" i j
    in

    (* serialize matrices and send it to python process *)
    let send_matrix fdd =
      Out_channel.fprintf to_py "%d %d\n" n n;
      Matrix.iter_fdd_entries fdd coding ~f:send_matrix_entry;
      (* SJS: although it is implicit in the FDD, the emptyset transitions with
         probability 1 to the emptyset
      *)
      let emptyset = Coding.Index0.emptyset in
      send_matrix_entry (emptyset.i, emptyset.i, Prob.one);
      Out_channel.fprintf to_py "\n%!";
    in

    Util.timed "sending fdds as matrices to python" (fun () ->
      Util.timed "sending ap" (fun () -> send_matrix ap);
      Util.timed "sending not_a" (fun () -> send_matrix not_a);
      Out_channel.close to_py
    )


  (*      X = (AP)*¬A
    Thus  X = ¬A + (AP)X
     <=>  (I-AP)X = ¬A
     We are looking for X. We solve the linear (sparse) system to compute it.
  *)
  let iterate a p =
    (* printf "a = %s\n" (to_string a); *)
    (* transition matrix for transient states, i.e. those satisfying predicate [a] *)
    let ap = prod a p in
    (* transition matrix for absorbing states, i.e. those not satisfying [a] *)
    let not_a = negate a in

    (* printf "ap = %s\n%!" (to_string ap); *)
    (* printf "not_a = %s\n%!" (to_string not_a); *)

    (* setup external python script to solve linear system, start in seperate process *)
    let pkg_name = "probnetkat" in
    let script_name = "absorption.pyc" in
    let pyscript = match Findlib.package_directory pkg_name with
      | dir ->
        dir ^ "/" ^ script_name
      | exception Findlib.No_such_package _ ->
        failwith ("missing ocamlfind dependency: " ^ pkg_name)
    in
    let cmd = "python3 " ^ pyscript in
    let (pid_py, from_py, to_py) = Util.Unix.open_process cmd in

    (* compute domain of FDDs; i.e., how many indices do we need for the matrix
       representation and what does each index preresent?
    *)
    let dom = Domain.(merge (of_fdd ap) (of_fdd not_a)) in
    let module Coding = Coding(struct let domain = dom end) in
    let coding = (module Coding : CODING) in

    (* try computing naive fixed-point and analytical fixed-point in parallel *)
    match Unix.fork () with
    | `In_the_child ->
      python_iterate ap not_a coding to_py;
      exit 0
    | `In_the_parent child ->
      (* parent process *)
      begin match fixpoint_race ap not_a ~child:(Pid.to_int child) with
      | Some fixpoint ->
        printf "*** ocaml won race!\n";
        (* kill forked process and return result *)
        Signal.(send_i kill (`Pid pid_py));
        Signal.(send_i kill (`Pid child));
        fixpoint
      | None ->
        printf "*** python won race!\n";
        (* wait for reply from Python *)
        let n = Domain.size dom in
        let iterated = Sparse.zeros n n in
        let line () = In_channel.input_line_exn from_py in

        Util.timed "receive result from python" (fun () ->
          begin try
            let (m,n') = String.lsplit2_exn (line ()) ~on:' ' in
            let (m,n') = Int.(of_string m, of_string n') in
            if m <> n || n' <> n then failwith "no bueno"
          with
            | End_of_file -> failwith "python process closed prematurely."
            | _ -> failwith "malformed first output line"
          end;

          begin try while true do
            match String.split (line ()) ~on:' ' with
            | [i; j; v] ->
              let i,j = Int.(of_string i, of_string j) in
              assert (0 <= i && i < n);
              assert (0 <= j && j < n);
              let v = Float.of_string v in
              Sparse.set iterated i j v
            | _ ->
              failwith "malformed output line"
          done with
            | End_of_file -> ()
            | _ -> failwith "malformed output line"
          end;
        );

        (* convert matrix back to FDD *)
        let iterated = Matrix.{ matrix = iterated; dom; coding } in
        Util.timed "matrix -> fdd conversion" (fun () ->
          of_mat iterated
        )
      end




  (** Erases (all matches on) meta field, then all modifications. *)
  let erase t meta_field init =
    let erase_mods =
      ActionDist.pushforward ~f:(function
        | Drop -> Drop
        | Action act -> Action (PreAction.T.remove act meta_field))
    in
    match init with
    | Const v ->
      restrict [(meta_field,v)] t
      |> map_r ~f:erase_mods
    | Alias alias ->
      fold t
        ~f:(fun dist -> const (erase_mods dist))
        ~g:(fun (field,v) tru fls ->
          if field = meta_field then
            cond (alias, v) tru fls
          else
            cond (field,v) tru fls
        )

  let rec of_pol_k (p : Field.t policy) k : t =
    match p with
    | Filter p ->
      k (of_pred p)
    | Modify m ->
      k (of_mod  m)
    | Seq (p, q) ->
      of_pol_k p (fun p' ->
        if equal p' Fdd0.drop then
          k drop
        else
          of_pol_k q (fun q' -> k (seq p' q')))
    | Ite (a, p, q) ->
      let a = of_pred a in
      if equal a id then
        of_pol_k p k
      else if equal a drop then
        of_pol_k q k
      else
        of_pol_k p (fun p ->
          of_pol_k q (fun q ->
            (* SJS: Disjoint union. Ideally, we would have a safe primitive for
               this purpose. Either way, the implementation of sum currently
               enforces that nothing can go wrong here.
             *)
            k @@ sum (prod a p) (prod (negate a) q)
          )
        )
    | While (a, p) ->
      let a = of_pred a in
      if equal a id then k drop else
      if equal a drop then k id else
      of_pol_k p (fun p ->
        k @@ Util.timed "while loop" (fun () -> iterate a p)
      )
    | Choice dist ->
      (* SJS: use n-ary convex sum *)
      failwith "not implemented"
(*       List.map dist ~f:(fun (p, prob) ->
        of_pol_k p (map_r ~f:(ActionDist.scale ~scalar:prob))
      )
      |> big_union *)
      |> k
    | Let { id=field; init; mut; body=p } ->
      of_pol_k p (fun p' -> k (erase p' field init))

  and of_symbolic_pol (p : Field.t policy) : t = of_pol_k p ident

  let of_pol (p : string policy) : t =
    allocate_fields p
    |> of_symbolic_pol

  type weighted_pk = Packet.t * Prob.t [@@deriving compare, eq]

  let equivalent ?(modulo=[]) t1 t2 =
    let rec do_nodes t1 t2 pk =
      match unget t1, unget t2 with
      | Branch ((f1,v1), l1, r1), Branch ((f2,v2), l2, r2) ->
        begin match Field.compare f1 f2 with
        | -1 ->
          do_nodes l1 t2 (PrePacket.modify pk f1 (Const v1)) &&
          do_nodes r1 t2 pk
        | 1 ->
          do_nodes t1 l2 (PrePacket.modify pk f2 (Const v2)) &&
          do_nodes t1 r2 pk
        | 0 ->
          begin match Value.compare v1 v2 with
          | 0 ->
            do_nodes l1 l2 (PrePacket.modify pk f1 (Const v1)) &&
            do_nodes r1 r2 pk
          | -1 ->
            do_nodes l1 r2 (PrePacket.modify pk f1 (Const v1)) &&
            do_nodes r1 t2 pk
          | 1 ->
            do_nodes r1 l2 (PrePacket.modify pk f2 (Const v2)) &&
            do_nodes t1 r2 pk
          | _ -> assert false
          end
        | _ -> assert false
        end
      | Branch ((f1,v1), l1, r1), Leaf _ ->
        do_nodes l1 t2 (PrePacket.modify pk f1 (Const v1)) &&
        do_nodes r1 t2 pk
      | Leaf _, Branch ((f2,v2), l2, r2) ->
        do_nodes t1 l2 (PrePacket.modify pk f2 (Const v2)) &&
        do_nodes t1 r2 pk
      | Leaf d1, Leaf d2 ->
        do_leaves d1 d2 pk
    and do_leaves d1 d2 pk =
      List.equal ~equal:equal_weighted_pk (normalize d1 pk) (normalize d2 pk)
    and normalize dist pk =
      ActionDist.to_alist dist
      |> Util.map_fst ~f:modulo_mods
      |> Util.map_fst ~f:(Packet.(apply (Pk pk)))
      |> List.sort ~cmp:compare_weighted_pk
    and modulo_mods act =
      match act with
      | Drop -> Drop
      | Action act ->
        let act = Field.Map.filteri act~f:(fun ~key:f ~data:_ ->
          let f = Map.find_exn (!Field.field_to_str_map) f in
          not @@ List.mem modulo f ~equal:String.equal)
        in
        Action act
    in
    do_nodes t1 t2 PrePacket.empty

end
