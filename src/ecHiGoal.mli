(* Copyright (c) - 2012-2014 - IMDEA Software Institute and INRIA
 * Distributed under the terms of the CeCILL-B license *)

(* -------------------------------------------------------------------- *)
open EcLocation
open EcParsetree
open EcCoreGoal
open EcCoreGoal.FApi

(* -------------------------------------------------------------------- *)
type ttenv = {
  tt_provers : EcParsetree.pprover_infos -> EcProvers.prover_infos;
  tt_smtmode : [`Admit | `Strict | `Standard];
}

type smtinfo = pdbhint option * pprover_infos
type engine  = ptactic_core -> backward

(* -------------------------------------------------------------------- *)
type cut_t    = intropattern * pformula * ptactic_core option
type cutdef_t = intropattern * pterm
type apply_t  = ffpattern * [`Apply of psymbol option | `Exact]

(* -------------------------------------------------------------------- *)
module LowApply : sig
  val t_apply_bwd : proofterm -> backward
end

(* -------------------------------------------------------------------- *)
module LowRewrite : sig
  val t_rewrite : [`LtoR|`RtoL] * EcMatching.occ option -> proofterm -> backward

  val t_autorewrite: EcPath.path list -> backward
end

(* -------------------------------------------------------------------- *)
val process_reflexivity : backward
val process_assumption  : backward
val process_intros      : ?cf:bool -> intropattern -> backward
val process_mintros     : ?cf:bool -> intropattern -> tactical
val process_generalize  : genpattern list -> backward
val process_clear       : psymbol list -> backward
val process_smt         : ttenv -> smtinfo -> backward
val process_apply       : apply_t -> backward
val process_rewrite     : ttenv -> (tfocus located option * rwarg1) list -> backward
val process_subst       : pformula list -> backward
val process_cut         : engine -> cut_t -> backward
val process_cutdef      : cutdef_t -> backward
val process_left        : backward
val process_right       : backward
val process_split       : backward
val process_elim        : genpattern list * pqsymbol option -> backward
val process_case        : genpattern list -> backward
val process_exists      : fpattern_arg located list -> backward
val process_congr       : backward
val process_trivial     : backward
val process_change      : pformula -> backward
val process_simplify    : preduction -> backward
val process_pose        : psymbol -> rwocc -> pformula -> backward
val process_done        : backward

(* -------------------------------------------------------------------- *)
val process_algebra : [`Solve] -> [`Ring|`Field] -> psymbol list -> backward
