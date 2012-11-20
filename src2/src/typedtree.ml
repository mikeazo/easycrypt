(* -------------------------------------------------------------------- *)
open Utils
open Parsetree

module UidGen : sig
  type uid = int
  type uidmap

  val create : unit -> uidmap
  val lookup : uidmap -> symbol -> uid option
  val forsym : uidmap -> symbol -> uid
end = struct
  type uid = int

  type uidmap = {
    (*---*) um_tbl : (symbol, uid) Hashtbl.t;
    mutable um_uid : int;
  }

  let create () =
    { um_tbl = Hashtbl.create 0;
      um_uid = 0; }

  let lookup (um : uidmap) (x : symbol) =
    try  Some (Hashtbl.find um.um_tbl x)
    with Not_found -> None

  let forsym (um : uidmap) (x : symbol) =
    match lookup um x with
      | Some uid -> uid
      | None ->
        let uid = um.um_uid in
          um.um_uid <- um.um_uid + 1;
          Hashtbl.add um.um_tbl x uid;
          uid
end

(* -------------------------------------------------------------------- *)
module Path = struct
  type path =
    | Pident of symbol
    | Pqname of symbol * path

  let rec create (path : string) =
    match try_nf (fun () -> String.index path '.') with
      | None   -> Pident path
      | Some i ->
        let qname = String.sub path 0 i in
        let path  = String.sub path i (String.length path - i) in
          Pqname (qname, create path)

  let toqsymbol =
    let rec toqsymbol scope = function
      | Pident x       -> (List.rev scope, x)
      | Pqname (nm, p) -> toqsymbol (nm :: scope) p
    in
      fun (p : path) -> toqsymbol [] p
end

(* -------------------------------------------------------------------- *)
type tybase = Tunit | Tbool | Tint | Treal

type ty =
  | Tbase   of tybase
  | Tvar    of UidGen.uid
  | Trel    of int
  | Ttuple  of ty list
  | Tconstr of Path.path * ty list

type tyexp =
  | Eunit                                   (* unit literal      *)
  | Ebool   of bool                         (* bool literal      *)
  | Eint    of int                          (* int. literal      *)
  | Eident  of Path.path * ty               (* symbol            *)
  | Eapp    of Path.path * tyexp list       (* rel. variable     *)
  | Elet    of lpattern * tyexp * tyexp     (* op. application   *)
  | Etuple  of tyexp list                   (* let binding       *)
  | Eif     of tyexp * tyexp * tyexp        (* tuple constructor *)
  | Ernd    of tyrexp                       (* _ ? _ : _         *)
                                            (* random expression *)

and tyrexp =
  | Rbool                                   (* flip               *)
  | Rinter    of tyexp * tyexp              (* interval sampling  *)
  | Rbitstr   of tyexp                      (* bitstring sampling *)
  | Rexcepted of tyrexp * tyexp             (* restriction        *)
  | Rapp      of Path.path * tyexp list     (* p-op. application  *)

(* -------------------------------------------------------------------- *)
let tunit () = Tbase Tunit
let tbool () = Tbase Tbool
let tint  () = Tbase Tint

module StdPath : sig
  val nil  : Path.path
  val cons : Path.path
end = struct
  let nil  = Path.create "<top>.nil"
  let cons = Path.create "<top>.cons"
end

let mknil  ()   = Eapp (StdPath.nil , [     ])
let mkcons x xs = Eapp (StdPath.cons, [x; xs])

(* -------------------------------------------------------------------- *)
module Scope : sig
  type scope

  val resolve : scope -> symbol -> (int * Path.path) option

  module Op : sig
    type op = {
      op_path : Path.path;
      op_probabilistic : bool;
    }

    val find   : scope -> qsymbol -> op option
    val select : op -> ty list -> op option
  end
end = struct
  type scope = unit

  let resolve _ _ = assert false

  module Op = struct
    type op = {
      op_path : Path.path;
      op_probabilistic : bool;
    }

    let find (scope : scope) (name : qsymbol) = None

    let select (op : op) (esig : ty list) = None
  end
end

(* -------------------------------------------------------------------- *)
type tyerror =
  | UnknownTypeName          of symbol
  | UnknownOperator          of qsymbol
  | InvalidNumberOfTypeArgs  of symbol * int * int
  | UnboundTypeParameter     of symbol
  | OpNotOverloadedForSig    of Scope.Op.op * ty list
  | UnexpectedType           of ty * ty
  | ProbaExpressionForbidden

exception TyError of tyerror

let tyerror x = raise (TyError x)

(* -------------------------------------------------------------------- *)
type typolicy = [
  | `TyDecl  of symbol list
  | `TyAnnot of UidGen.uidmap
]

let transty (scope : Scope.scope) (policy : typolicy) =
  let rec transty = function
      (* Base types *)
    | Punit        -> Tbase Tunit
    | Pbool        -> Tbase Tbool
    | Pint         -> Tbase Tint
    | Preal        -> Tbase Treal
    | Pbitstring _ -> assert false        (* FIXME *)
    | Ptuple tys   -> Ttuple (List.map transty tys)

    | Pnamed name -> begin
      match Scope.resolve scope name with (* FIXME *)
        | None -> tyerror (UnknownTypeName name)
        | Some (i, p) ->
          if i <> 0 then
            tyerror (InvalidNumberOfTypeArgs (name, 0, i));
          Tconstr (p, [])
    end

    | Papp (name, tyargs) -> begin
      match Scope.resolve scope name with
        | None -> tyerror (UnknownTypeName name)
        | Some (i, p) ->
          let nargs = List.length tyargs in
            if i <> List.length tyargs then
              tyerror (InvalidNumberOfTypeArgs (name, i, nargs));
            let tyargs = List.map transty tyargs in
              Tconstr (p, tyargs)
    end

    | Pvar a -> begin
      match policy with
        | `TyDecl tyvars -> begin
          match List.index a tyvars with
            | None   -> tyerror (UnboundTypeParameter a)
            | Some i -> Trel i
        end

        | `TyAnnot uidmap -> Tvar (UidGen.forsym uidmap a)
    end
  in
    fun ty -> transty ty

(* -------------------------------------------------------------------- *)
module Env = struct
  type env = unit

  let bind (_ : symbol * ty) (e : env) = (failwith "" : env)
end

type epolicy = {
  epl_probabilistic : bool;
}

(* -------------------------------------------------------------------- *)
let transexp (scope : Scope.scope) =
  let rec transexp (env : Env.env) (policy : epolicy) = function
    | PEunit   -> (Eunit  , tunit ())
    | PEbool b -> (Ebool b, tbool ())
    | PEint  i -> (Eint  i, tint  ())

    | PEapp (name, es) -> begin
      match Scope.Op.find scope name with
        | None    -> tyerror (UnknownOperator name)
        | Some op ->
          if op.Scope.Op.op_probabilistic && not (policy.epl_probabilistic) then
            tyerror ProbaExpressionForbidden;
          let es   = List.map (transexp env policy) es in
          let esig = snd (List.split es) in
            match Scope.Op.select op esig with
              | None      -> tyerror (OpNotOverloadedForSig (op, esig))
              | Some _idx -> begin
                match op.Scope.Op.op_probabilistic with
                  | true  -> (Ernd (Rapp (op.Scope.Op.op_path, List.map fst es)), tunit ()) (* FIXME *)
                  | false -> (Eapp (op.Scope.Op.op_path, List.map fst es), tunit ()) (* FIXME *)
              end
    end

    | PElet (p, e1, e2) -> begin
      let e1, ty1 = transexp env policy e1 in
      let e2, ty2 =
        match p with
          | LPSymbol x  -> transexp (Env.bind (x, ty1) env) policy e2
          | LPTuple  xs ->
            let tyvars = List.map (fun _ -> Tvar (mktyvar ())) xs in
              if not (Unify.unify (Ttuple tyvars) ty1) then
                tyerror (UnexpectedType (Ttuple tyvars, ty1));
              transexp (Env.bindall (List.combine xs tyvars) env) policy e2
      in
        (e2, ty2)
    end

    | PEtuple es ->
      let es, tys =
        List.split (List.map (transexp env policy) es)
      in
        (Etuple es, Ttuple tys)

    | PEif (c, e1, e2) ->
      let c, tyc = transexp env policy c in
        if not (Unify.unify tyc (tbool ())) then
          tyerror (UnexpectedType (tyc, (tbool ())));
        let e1, ty1 = transexp env policy e1 in
        let e2, ty2 = transexp env policy e2 in
          if not (Unify.unify ty1 ty2) then
            tyerror (UnexpectedType (ty1, ty2));
          (Eif (c, e1, e2), ty1)

    | PErnd re ->
      if not policy.epl_probabilistic then
        tyerror ProbaExpressionForbidden;
      let re, ty = transrexp env policy in
        (Ernd re, ty)

  and transrexp (env : env) (policy : policy) = function
    | PRbool -> (Rbool, Tbool)

(*
    | PRinter (e1, e2) ->
      let e1, ty1 = transexp e1 in
      let e2, ty2 = transexp e2 in
        

                               (* flip               *)
  | PRinter    of expr * expr             (* interval sampling  *)
  | PRbitstr   of expr                    (* bitstring sampling *)
  | PRexcepted of rexpr * expr            (* restriction        *)
  | PRapp      of symbol * expr list      (* p-op. application  *)
*)
  in
    ()
