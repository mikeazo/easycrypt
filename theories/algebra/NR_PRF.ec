(* NR-PRF *)
require import Int Real List SmtMap Distr DList FSet PROM.
require (*--*) GroupAction PRF Word BitWord.

(* We need a regular, effective, abelian group action for this construction *)
clone import GroupAction.ARegEGA as Ega.

(* This function should compute the action of a list of group elements masked by an equal sized list of booleans *)
op compute_action (gs : group list) (ss : bool list) (x : set) : set =
    with gs = "[]"     ,      ss = "[]" => x
    with gs = "[]"     , ss = (::) s ss => x
    with gs = (::) g gs,      ss = "[]" => x
    with gs = (::) g gs, ss = (::) s ss =>
      if s then compute_action gs ss (act g x)
           else compute_action gs ss x.

op l : {int | 0 < l} as gt0_l.

clone import Word as GroupWord with
  type Alphabet.t <- group,
  op n <- l + 1
proof
 ge0_n by smt(gt0_l)
rename
  "word" as "key"
  "dunifin" as "dkey".

clone import BitWord as S with
  op n <- l
proof
  ge0_n by smt(gt0_l)
rename
  "word" as "bits".

(* Setup keyspace, domain, and range *)
type K = key.
type D = bits. (* Only one bit for the moment but will be an l-bit word *)
type R = set.

(* This is the Naor-style PRF construction *)
op F (k : K) (m : D) = compute_action (behead (ofkey k)) (ofbits m) (act k.[0] x0).

(* Setup the uniform distribution on our range *)
clone import MFinite as Uni_dR with
  type t <- R
rename
  "dunifin" as "dR".

(* Setting up the PRF *)
clone import PRF as PRF_t with
  type D <- D,
  type R <- R.

clone import RF as NS_RF with
  op dR _ <- dR
proof *.
realize dR_ll.
by move=> _; exact dR_ll.
qed.

clone import PseudoRF as NS_PRF with
  type K <- K,
  op dK <- dmap (dlist sample (l + 1)) mkkey,
  op F <- F
proof *.
realize dK_ll.
exact/dmap_ll/dlist_ll/DG.dunifin_ll.
qed.

(* A very useful lemma that shows that dR ~= sample *)
lemma sample_dR_iso g x: mu1 sample g = mu1 dR (act g x).
proof.
have /= <- := dmap1E_can dR (extract x) (fun g=> act g x) g _ _.
+ by rewrite /cancel=> g'; rewrite -extractUniq.
+ by move=> a _ /=; rewrite extractP.
congr; apply: eq_funi_ll.
+ exact: DG.dunifin_funi.
+ exact: DG.dunifin_ll.
+ apply/dmap_funi.
  + exists (fun g=> act g x); split.
    + by move=> a; exact: extractP.
    by move=> h; rewrite -extractUniq.
  exact: dR_funi.
exact/dmap_ll/Uni_dR.dR_ll.
qed.

(* ----------------------------------------------- *)
(* Weak pseudorandomness assumption *)
module type WP = {
    proc init() : unit
    proc query() : R * R
}.

module type Bounded_WP = {
    proc init(_ : int) : unit
    proc query() : R * R
}.

module type WP_Oracles = {
    proc query() : R * R
}.

module type WP_Adv (F : WP_Oracles) = {
  proc distinguish () : bool
}.

module WP_IND (F : WP) (A : WP_Adv) = {
  proc main() : bool = {
    var b : bool;
    F.init();
    b <@ A(F).distinguish();
    return b;
  }
}.

module BoundWP(O : WP) : Bounded_WP = {
    var q, c : int
    proc init(Q : int) = {
        O.init();
        q <- Q;
        c <- 1;
    }

    proc query() = {
        var r : set * set;
        r <- witness;
        if (c <= q) {
            r <@ O.query();
        }
        return r;
    }
}.

module WP_Real = {
    var g : group
  
    proc init() = { g <$ sample; }

    proc query() = {
        var xq, yq : set;
        xq <$ dR;
        yq <- act g xq;
        return (xq, yq);
    }
}.

module WP_Ideal = {
    proc init() = { }

    proc query() = {
        var xq, yq : set;
        xq <$ dR;
        yq <$ dR;
        return (xq, yq);
    }
}.

(* ------------------------------------------------------ *)
(* Setup our bounding module *)

module type Bounded_PRF = {
    proc init(_ : int) : unit
    proc f(_ : D) : R
}.

module Bounded_PRF_IND (F : Bounded_PRF) (A : Distinguisher) = {
    proc main (Q : int) : bool = {
        var b : bool;
        F.init(Q);
        b <@ A(F).distinguish();
        return b;
    }
}.

module BoundPRF(O : PRF_t.PRF) : Bounded_PRF = {
    var c, q : int
    
    proc init(Q : int) : unit = {
        O.init();
        q <- Q;
        c <- 1;
    }

    proc f(x : D) : R = {
        var val : R;
        val <- witness;
        if (c <= q) {
            val <@ O.f(x);
            c <- c + 1;
        }
        return val;
    }
}.

(** Define the final reduction(s) **)
(** module R (D : PRF_Distinguisher) (WP : WP_Oracles) = {
      proc distinguish(J, Q) = {
        An inlined version of R(Bj(D)).distinguish(J, Q);
      }
    }
**)

section PRF_Security.
declare module D : Distinguisher { BoundPRF, PRF, RF }.

(* ---------------------------------------------------------------------------------------- *)

(* The hybrid used for the proof of Theorem 4.19 *)
(* This hybrid slowly replaces each action of a gi on x0 with the random sampling of a set element *)
(* The 0th hybrid should exactly represent a Pseudorandom function and the Lth hybrid a truly random function *)
local clone import PROM.FullRO as G0_RO with
  type in_t <- unit,
  type out_t <- group,
  type d_in_t <- unit,
  type d_out_t <- bool,
  op dout _ <- sample.

local module G0 = RO.
local module LG0 = FullEager.LRO.

local module Hj (G0 : G0_RO.RO) = {
  (* Our hybrid parameter *)
  var j   : int

  var gis : group list (* In the general case this will be a list of group elements of size l - j *)

  var yqs : (bool list, set) fmap (* Store any previous query's result *)

  (* Query bounding variables *)
  var c   : int
  var q   : int

  module O = {
    proc f(x) = {
      var xs <- ofbits x;
      var  p <- take j xs;
      var  s <- drop j xs;
      var gq;
      var yq;
      var r <- witness;
      var g;

      if (c <= q) {
        (* We have a special case for the 0th hybrid *)
        if (j = 0) {
          g <@ G0.get();
          yq <- act g x0;
        } else {
          if (p \notin yqs) {
            gq <$ sample; (* FIXME: When the PRF theory is updated this line should be moved before the if *)
            yqs.[p] <- act gq x0;
          }
          yq <- oget (yqs.[p]);
        }
        c <- c + 1;
        r <- compute_action gis s yq;
      }
      return r;
    }
  }

  proc run(i : int, Q : int) : bool = {
    var b;

      j <- i;
      c <- 1;
      q <- Q;
    G0.init();
    G0.sample();
    gis <$ dlist sample (l - j);
    yqs <- empty;

      b <@ D(O).distinguish();
    return b;
  }
}.

local clone import Program with
  type t <- group,
  op d <- sample.

local equiv PRF_Hybrid0:
  Bounded_PRF_IND(BoundPRF(PRF), D).main ~ Hj(G0).run:
    ={glob D, Q} /\ 0 <= Q{1} /\ i{2} = 0
    ==> ={res}.
proof.
proc=> /=.
call (:    Hj.j{2} = 0
        /\ ={q, c}(BoundPRF, Hj)
        /\ size Hj.gis{2} = l - Hj.j{2}
        /\ () \in G0.m{2}
        /\ PRF.k{1} = mkkey ((oget G0.m.[()]) :: Hj.gis){2}).
+ proc; sp; if; 1,3:auto.
  inline *.
  rcondt {2} 1; 1:by auto.
  rcondf {2} 3; 1:by auto.
  auto=> /> &2 gis_size tt_in c_le_q g gin @/F /=.
  rewrite drop0 getE ofkeyK /= 1:gis_size 1:addzC //.
  smt(gt0_l).
inline *; sp; wp; conseq />.
rcondt {2} 2.
+ auto=> /> &2.
  by rewrite mem_empty.
swap {2} 3 -2.
wp.
transitivity {2}
    {Hj.gis <@ SampleCons.sample(l + 1);}
    (true ==> PRF.k{1} = mkkey Hj.gis{2})
    (x0{2} = tt /\ Hj.j{2} = 0 ==> x0{2} = tt /\ size Hj.gis{2} = l /\ Hj.gis{1} = (r :: Hj.gis){2})=> //.
+ move=> &1 &m &2 ->.
  case=> x_eq + /=.
  case=> -> /=.
  rewrite x_eq domE !get_set_sameE //= => ^ + -> /=.
+ transitivity {2}
    {Hj.gis <@ Sample.sample(l + 1);}
    (true ==> PRF.k{1} = mkkey Hj.gis{2})
    (true ==> ={Hj.gis})=> //; first last.
    + by call Sample_SampleCons_eq; auto=> /=; smt(gt0_l).
    inline *; sp; wp.
    rnd ofkey mkkey.
    auto=> />.
    split.
    + move=> gis gis_in.
      rewrite ofkeyK.
      + by move: gis_in; apply supp_dlist_size; smt(gt0_l).
      trivial.
    move=> a.
    split.
    + move=> gis gis_in.
      rewrite (dmap1E_can _ mkkey ofkey).
      + exact mkkeyK.
      + by move=> r /(a r); rewrite eq_sym.
      by rewrite {1}(a gis gis_in).
    move=> b.
    move=> k kin.
    rewrite mkkeyK /= -(size_key k).
    apply dlist_fu=> x _.
    exact DG.dunifin_fu.
inline *.
auto=> />gis + _ _.
apply supp_dlist_size.
smt(gt0_l).
qed.

local lemma PRF_Hybrid0_pr q &m:
     0 <= q
  =>   Pr[Bounded_PRF_IND(BoundPRF(PRF), D).main(q) @ &m: res]
     = Pr[Hj(G0).run(0, q) @ &m: res].
proof. by move=> ge0_q; byequiv PRF_Hybrid0. qed.

local equiv PRF_HybridL:
  Bounded_PRF_IND(BoundPRF(RF), D).main ~ Hj(G0).run:
    ={glob D, Q} /\ 0 <= Q{1} /\ i{2} = l
    ==> ={res}.
proof.
proc=> /=; inline *.
call (:    Hj.j{2} = l
        /\ ={q, c}(BoundPRF, Hj)
        /\ (forall (p : bool list), p \in Hj.yqs{2} => size p = l)
        /\ (forall (x : D), RF.m.[x]{1} = Hj.yqs.[ofbits x]{2})).
+ proc; sp; if; auto.
  rcondf {2} 1; 1:by auto; smt(gt0_l).
  inline *.
  sp; if=> /=.
  + auto=> /> &1 &2 size_p val_eq c_le_q.
    rewrite !domE !(val_eq x{2}) -!domE.
    split.
    + move=> ^ + /size_p <-.
      by rewrite take_size.
    by rewrite take_oversize 1:size_bits.
  + wp.
    rnd (fun x => extract x0 x) (fun g => act g x0).
    skip=> /> &1 &2 size_p val_eq c_le_q nin.
    split=> [g _ | _]; first exact extractUniq.
    split=> [g _ | _ r _]; first exact sample_dR_iso.
    rewrite extractP !get_set_sameE /=.
    rewrite drop_oversize 2:take_oversize 1,2:size_bits //=.
    split; first case (Hj.gis{2})=> />.
    split.
    + move=> p.
      rewrite domE get_setE.
      case (p = ofbits x{2})=> /=.
      + move=> ->.
        exact size_bits.
      rewrite -domE=> _.
      exact size_p.
    move=> x'.
    rewrite !get_setE.
    case (x' = x{2})=> />.
    case (ofbits x' = ofbits x{2}).
    + by move=> /ofbits_inj.
    by move: (val_eq x')=> ->.
  auto=> &1 &2 /> size_p eqv c_le_q xin.
  search drop size.
  rewrite -(size_bits x{2}) drop_size take_size eqv.
  by case (Hj.gis{2})=> />.
rcondt {2} 8.
+ auto=> /> &2.
  by rewrite mem_empty.
auto=> /> &2 _ g _ x.
smt(emptyE).
qed.

local lemma PRF_HybridL_pr q &m:
     0 <= q
  =>   Pr[Bounded_PRF_IND(BoundPRF(RF), D).main(q) @ &m: res]
     = Pr[Hj(G0).run(l, q) @ &m: res].
proof. by move=> ge0_q; byequiv PRF_HybridL. qed.

(* Simple reduction statement for the case of l = 1 *)
local lemma Hybrid_PRF_Reduction (q : int) &m :
    0 <= q
 =>  `|Pr[Bounded_PRF_IND(BoundPRF(PRF), D).main(q) @ &m: res] - Pr[Bounded_PRF_IND(BoundPRF(RF), D).main(q) @ &m: res]|
   = `|Pr[Hj(G0).run(0, q) @ &m: res] - Pr[Hj(G0).run(l, q) @ &m: res]|.
by move=> z_le_q; rewrite (PRF_HybridL_pr q &m z_le_q) (PRF_Hybrid0_pr q &m z_le_q).
qed.

equiv prf_bound_eq (D <: Distinguisher) (O <: PRF) :
  D(O).distinguish ~ D(BoundPRF(O)).distinguish:
      ={glob D, glob O} /\ BoundPRF.c{1} = 1 /\ BoundPRF.c{2} = 1
  ==> ={res}.
proof.
admit.
qed.

(* -------------------------------------------------------- *)
(* Proving the hybrid reduction of lemma 4.21/ theorem 4.19 *)
local clone import PROM.FullRO as XRO_t with
  type in_t    <- bool list,
  type out_t   <- R,
  type d_in_t  <- unit,
  type d_out_t <- bool,
    op dout _  <- dR. (* Might need to change this, who knows? *)

local module X  = RO.
local module LX = FullEager.LRO.

local clone import PROM.FullRO as YRO_t with
  type in_t    <- bool list,
  type out_t   <- R,
  type d_in_t  <- unit,
  type d_out_t <- bool,
    op dout _  <- dR. (* Might need to change this, who knows? *)

local module Y  = RO.
local module LY = FullEager.LRO.

local clone import PROM.FullRO as XYRO_t with
  type in_t    <- bool list,
  type out_t   <- R * R,
  type d_in_t  <- unit,
  type d_out_t <- bool,
    op dout _  <- dR `*` dR.

local module XY  = RO.
local module LXY = FullEager.LRO.

local module XY_Real = {
    var m : (bool list, R * R) fmap
    var g : group

    proc init() = {
      g <$ sample;
      m <- empty;
    }

    proc get(x) = {
      var xq, yq : set;

      if (x \notin m) {
        xq <$ dR;
        yq <- act g xq;
        m.[x] <- (xq, yq);
      }
      return oget m.[x];
    }

    proc set(x, y) = {
      m.[x] <- y;
    }

    proc rem(x) = {
      m <- SmtMap.rem m x;
    }

    proc sample(x) = {
      get(x);
    }

    proc restrK() = {
      return m;
    }
}.

local module DecompWP (O : WP) = {
  var m : (bool list, R * R) fmap

  proc init() = {
         O.init();
    m <- empty;
  }

  proc get(x) = {
    var xy;

    if (x \notin m) {
         xy <@ O.query();
      m.[x] <- xy;
    }
    return oget m.[x];
  }

  proc set(x, y) = {
    m.[x] <- y;
  }

  proc rem(x) = {
    m <- SmtMap.rem m x;
  }

  proc sample(x) = {
    get(x);
  }

  proc restrK() = {
    return m;
  }
}.

local module R (D : RO_Distinguisher) (O : WP_Oracles) = {
  module O' = {
    proc init = WP_Real.init
    proc query = O.query
  }

  proc distinguish() = {
    var b;

         DecompWP(O').init();
    b <@ D(DecompWP(O')).distinguish();
    return b;
  }
}.

local equiv XY_WP_Ideal (D <: RO_Distinguisher { XY, WP_Ideal, WP_Real, DecompWP }):
  MainD(D, XY).distinguish ~ WP_IND(WP_Ideal, R(D)).main:
    ={glob D} ==> ={res}.
proof.
proc; inline *; wp.
call (: ={m}(XY, DecompWP))=> //.
+ by proc; inline *; auto.
+ proc; if {2}; last by auto.
  rcondt {1} 2; first by auto.
  inline *.
  auto.
  admit.
+ by sim.
+ by sim.
+ proc; inline *; sp; if {2}; last by auto.
  rcondt {1} 2; first by auto.
  inline *; auto. admit.
by inline *; auto.
qed.

local equiv XY_WP_Real ( D <: RO_Distinguisher { XY_Real, WP_Real, DecompWP }):
  MainD(D, XY_Real).distinguish ~ WP_IND(WP_Real, R(D)).main:
    ={glob D} ==> ={res}.
proof.
proc; inline *; wp.
call (: ={m}(XY_Real, DecompWP) /\ ={g}(XY_Real, WP_Real))=> //.
+ by proc; inline *; auto.
+ by proc; if=> //; inline *; auto.
+ by sim.
+ by sim.
+ by proc; inline *; sp; if=> //; inline *; auto.
by inline *; auto.
qed.

(** The hybrid—distinguishes random {(xq,yq)} from pseudorandom {(xq,yq)}
    We index the family with query prefixes because we don't really
    care about what the index is: we;; run a hybrid over it anyway
**)
local module Bj (XYs : RO) = {
  var j   : int

  var gis : group list

  var c   : int
  var q   : int

  module O = {
    proc f(x) = {
      var xq, yq;
      var xs <- ofbits x;
      var  p <- take j xs;
      var  b <- nth witness xs j;
      var  s <- drop (j + 1) xs;
      var  r <- witness;

      if (c <= q) {
        (xq, yq) <@ XYs.get(p);
        r <- compute_action gis s (if b then yq else xq);
        c <- c + 1;
      }
      return r;
    }
  }

  proc distinguish(J, Q) = {
    var b;
           XYs.init();
      j <- J;
      c <- 1;
      q <- Q;
    gis <$ dlist sample (l - j - 1); (* This should only sample for indices [j+2, l] *)
      b <@ D(O).distinguish();
    return b;
  }
}.

(** In this version of the hybrids, we only sample the value that's needed **)
local module B' (Xs : XRO_t.RO) (Ys : YRO_t.RO) = {
  var j   : int

  var gis : group list

  var c   : int
  var q   : int

  module O = {
    proc f(x) = {
      var xs <- ofbits x;
      var  p <- take j xs;
      var  b <- nth witness xs j;
      var  s <- drop (j + 1) xs;
      var  r <- witness;

      if (c <= q) {
        if (b) {
               Xs.sample(p);
          r <@ Ys.get(p);
        } else {
          r <@ Xs.get(p);
               Ys.sample(p);
        }
        r <- compute_action gis s r;
        c <- c + 1;
      }
      return r;
    }
  }

  proc distinguish(J, Q) = {
    var b;
           Xs.init();
           Ys.init();
      j <- J;
      c <- 1;
      q <- Q;
    gis <$ dlist sample (l - j - 1); (* This should only sample for indices [j+2, l] *)
      b <@ D(O).distinguish();
    return b;
  }
}.

local clone import DProd.ProdSampling as ProdR with
  type t1 <- R,
  type t2 <- R.

(** Simple wrappers to consider distinguishers against one or the other RO **)
local module B'_X (Y : YRO_t.RO) (X : XRO_t.RO) = {
  proc distinguish() = {
    var b;

    b <@ B'(X, Y).distinguish(B'.j, B'.q);
    return b;
  }
}.

local module B'_Y (X : XRO_t.RO) (Y : YRO_t.RO) = {
  proc distinguish() = {
    var b;

    b <@ B'(X, Y).distinguish(B'.j, B'.q);
    return b;
  }
}.

local equiv split_XY:
    Bj(XY).distinguish ~ B'(LX, LY).distinguish:
          ={glob D, arg}
      ==> ={glob D, res}.
proof.
transitivity
  B'_X(LY, X).distinguish
  (={glob D} /\ arg{1} = (B'.j, B'.q){2} ==> ={glob D, res})
  (={glob D, glob X, glob Y} /\ arg{2} = (B'.j, B'.q){1} ==> ={glob D, res})=> // [/#||]; last first.
+ transitivity
    B'_X(LY, LX).distinguish
    (={glob D, glob X, glob Y, glob B'} ==> ={glob D, res})
    (={glob D, glob X, glob Y} /\ arg{2} = (B'.j, B'.q){1} ==> ={glob D, res})=> // [/#||].
  + conseq (XRO_t.FullEager.RO_LRO_D (B'_X(LY)) _)=> />.
    exact: (dR_ll witness).
  by proc; inline *; sim.
transitivity
  B'_Y(X, Y).distinguish
  (={glob D} /\ arg{1} = (B'.j, B'.q){2} ==> ={glob D, res})
  (={glob D, glob X, glob Y, glob B'} ==> ={glob D, res})=> // [/#||]; last first.
+ transitivity
    B'_Y(X, LY).distinguish
    (={glob D, glob X, glob Y, glob B'} ==> ={glob D, res})
    (={glob D, glob X, glob Y, glob B'} ==> ={glob D, res})=> // [/#||].
  + conseq (YRO_t.FullEager.RO_LRO_D (B'_Y(X)) _)=> />.
    exact: (dR_ll witness).
  by proc; inline *; sim.
transitivity
  B'(X, Y).distinguish
  (={glob D, arg} ==> ={glob D, res})
  (={glob D, glob X, glob Y} /\ arg{1} = (B'.j, B'.q){2} ==> ={glob D, res})=> // [/#||]; last first.
+ by proc; inline *; sim.
(** This should really have been kept as a separate lemma **)
proc.
call (:    ={j, c, q, gis}(Bj, B')
        /\ (forall p x y,
                  XY.m{1}.[p] = Some (x, y)
              <=> (X.m{2}.[p] = Some x /\ Y.m{2}.[p] = Some y))
        /\ (forall p, p \in X.m{2} <=> p \in Y.m{2})).
+ proc=> /=; sp; if; auto.
  if {2}; inline *.
  + swap {2} 6 -3.
    exists * RO.m.[p]{1}; elim * => - [|[] xq yq].
    + rcondt {1} 3; 1:by auto=> /#.
      rcondt {2} 5.
      + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
        pose p := take Bj.j{m} (ofbits x{m}).
        rewrite !domE=> //= xy_p val_inv dom_inv.
        by move: (val_inv p) xy_p; case: (XY.m.[p]{m})=> /#.
      rcondt {2} 7.
      + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
        pose p := take Bj.j{m} (ofbits x{m}).
        rewrite !domE=> //= xy_p val_inv dom_inv.
        by move: (val_inv p) xy_p; case: (XY.m.[p]{m})=> /#.
      sp; auto; conseq (: r0{1} = (r1,r0){2}).
      + move=> /> &1 &2 /eq_sym.
        pose p := take Bj.j{2} (ofbits x{2}).
        move=> xy_p val_inv dom_inv _ _ r0 r1; rewrite !get_setE //=.
        smt(get_setE).
      transitivity {1}
        {r0 <@ ProdR.S.sample(dR, dR); }
        (true ==> ={r0})
        (true ==> r0{1} = (r1, r0){2})=> //.
      + by inline {2} 1; auto.
      transitivity {2}
        { (r1, r0) <@ ProdR.S.sample2(dR, dR); }
        (true ==> r0{1} = (r1, r0){2})
        (true ==> ={r0, r1})=> //.
      + by call ProdR.sample_sample2; auto=> /> [].
      by swap {2} 1 1; inline {1} 1; auto.
    rcondf {1} 3; 1:by auto=> /#.
    rcondf {2} 5.
    + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
      pose p := take Bj.j{m} (ofbits x{m}).
      rewrite !domE=> //= xy_p val_inv dom_inv.
      by move: (val_inv p xq yq); rewrite xy_p=> /> ->.
    rcondf {2} 6.
    + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
      pose p := take Bj.j{m} (ofbits x{m}).
      rewrite !domE=> //= xy_p val_inv dom_inv.
      by move: (val_inv p xq yq); rewrite xy_p=> /> _ ->.
    sp; auto; conseq (: r0{1} = (r1,r0){2}).
    + move=> /> &1 &2 /eq_sym.
      pose p := take B'.j{2} (ofbits x{2}).
      by move=> xy_p /(_ p xq yq) + _ _ _; rewrite xy_p=> /> _ ->.
    transitivity {1}
      {r0 <@ ProdR.S.sample(dR, dR); }
      (true ==> ={r0})
      (true ==> r0{1} = (r1, r0){2})=> //.
    + by inline {2} 1; auto.
    transitivity {2}
      { (r1, r0) <@ ProdR.S.sample2(dR, dR); }
      (true ==> r0{1} = (r1, r0){2})
      (true ==> ={r0, r1})=> //.
    + by call ProdR.sample_sample2; auto=> /> [].
    by swap {2} 1 1; inline {1} 1; auto.
  swap {2} 7 -4.
  exists * RO.m.[p]{1}; elim * => - [|[] xq yq].
  + rcondt {1} 3; 1:by auto=> /#.
    rcondt {2} 4.
    + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
      pose p := take Bj.j{m} (ofbits x{m}).
      rewrite !domE=> //= xy_p val_inv dom_inv.
      by move: (val_inv p) xy_p; case: (XY.m.[p]{m})=> /#.
    rcondt {2} 8.
    + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
      pose p := take Bj.j{m} (ofbits x{m}).
      rewrite !domE=> //= xy_p val_inv dom_inv.
      by move: (val_inv p) xy_p; case: (XY.m.[p]{m})=> /#.
    sp; auto; conseq (: r0{1} = (r0,r1){2}).
    + move=> /> &1 &2 /eq_sym.
      pose p := take B'.j{2} (ofbits x{2}).
      move=> xy_p val_inv dom_inv _ _ r0 r1; rewrite !get_setE //=.
      smt(get_setE).
    transitivity {1}
      {r0 <@ ProdR.S.sample(dR, dR); }
      (true ==> ={r0})
      (true ==> r0{1} = (r0, r1){2})=> //.
    + by inline {2} 1; auto.
    transitivity {2}
      { (r0, r1) <@ ProdR.S.sample2(dR, dR); }
      (true ==> r0{1} = (r0, r1){2})
      (true ==> ={r0, r1})=> //.
    + by call ProdR.sample_sample2; auto=> /> [].
    by inline {1} 1; auto.
  rcondf {1} 3; 1:by auto=> /#.
  rcondf {2} 4.
  + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
    pose p := take Bj.j{m} (ofbits x{m}).
    rewrite !domE=> //= xy_p val_inv dom_inv.
    by move: (val_inv p xq yq); rewrite xy_p=> /> ->.
  rcondf {2} 7.
  + auto=> /> &0 /eq_sym + + + _ _ _ _ _ _.
    pose p := take Bj.j{m} (ofbits x{m}).
    rewrite !domE=> //= xy_p val_inv dom_inv.
    by move: (val_inv p xq yq); rewrite xy_p=> /> _ ->.
  sp; auto; conseq (: r0{1} = (r0,r1){2}).
  + move=> /> &1 &2 /eq_sym.
    pose p := take B'.j{2} (ofbits x{2}).
    by move=> xy_p /(_ p xq yq) + _ _ _; rewrite xy_p=> /> ->.
  transitivity {1}
    {r0 <@ ProdR.S.sample(dR, dR); }
    (true ==> ={r0})
    (true ==> r0{1} = (r0, r1){2})=> //.
  + by inline {2} 1; auto.
  transitivity {2}
    { (r0, r1) <@ ProdR.S.sample2(dR, dR); }
    (true ==> r0{1} = (r0, r1){2})
    (true ==> ={r0, r1})=> //.
  + by call ProdR.sample_sample2; auto=> /> [].
  by inline {1} 1; auto.
by inline *; auto=> /> _ _ _ p x y; rewrite !emptyE.
qed.

local lemma HSj_BjI (j : int):
  0 <= j < l => equiv[Hj(G0).run ~ Bj(XY).distinguish:
    ={glob D, Q} /\ i{1} = j + 1 /\ J{2} = j  /\ 0 <= Q{1}
    ==> ={res}].
proof.
move=> z_le_j_l_l.
transitivity
  B'(LX, LY).distinguish
  (={glob D, Q} /\ i{1} = j+1 /\ J{2} = j /\ 0 <= Q{1} ==> ={res})
  (={glob D, arg} ==> ={res})=> // [/#||]; last first.
+ by symmetry; conseq split_XY.
proc; sp=> //=.
call (:    B'.j{2} = j /\ Hj.j{1} = j + 1
        /\ ={c, q, gis}(Hj, B')
        /\ size B'.gis{2} = l - B'.j{2} - 1
        /\ (forall p, p \in Hj.yqs{1} => size p = Hj.j{1})
        /\ (forall p, p \in Y.m{2} => size p = B'.j{2})
        /\ (forall p, p \in X.m{2} => size p = B'.j{2})
        /\ (forall p, Y.m.[p]{2} = Hj.yqs.[rcons p true]{1})
        /\ (forall p, X.m.[p]{2} = Hj.yqs.[rcons p false]{1})
        (** yqs[p' ++ [b]] = yq; _qs[p'] = (xq, gt * xq) **)).
+ proc; sp; if; 1,3:by auto.
  rcondf {1} 1; 1:by auto=> /#.
  inline *.
  if {2}.
  + if {1}; [rcondt {2} 4|rcondf {2} 4].
    + auto=> /> &0 _ _ _ _ /(_ (take j (ofbits x{m}))).
      rewrite (take_nth witness).
      + by rewrite size_bits.
      move=> + + + ->.
      by rewrite !domE=> /= <-.
    + auto; symmetry; rnd (extract x0) (fun g=> act g x0).
      auto=> /> &1 &2 B_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj x_notin_yqs.
      split=> [g _|_]; 1:exact: extractUniq.
      split=> [g _|_ r _]; 1:exact: sample_dR_iso.
      rewrite extractP !get_set_sameE /=.
      do! split=> p.
      + rewrite mem_set=> - [/domR_size | ->] //.
        by rewrite size_take [smt(size_bits)].
      + rewrite mem_set=> - [/domLy_size | ->] //.
        by rewrite size_take [smt(size_bits)].
      + rewrite (take_nth witness) 1:size_bits // xj !get_setE.
        case (p = take j (ofbits x{1}))=> //.
        case (rcons p true = rcons (take j (ofbits x{1})) true).
        + by rewrite -!cats1=> /catIs.
        move=> _ _.
        exact valLRy.
      rewrite (take_nth witness) 1:size_bits // xj !get_setE.
      case (rcons p false = rcons (take j (ofbits x{1})) true)=> />.
      + by move=> /rconsIs.
      move=> _.
      exact valLRx.
    + auto=> /> &1 Hj_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj + _ _.
      by rewrite (take_nth witness) 1:size_bits // xj !domE -valLRy.
    auto=> /> &1 &2 B_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj x_in_yqs _ _.
    congr; congr.
    by rewrite valLRy (take_nth witness) 1:size_bits // xj.
  if {1}; [rcondt {2} 3|rcondf {2} 3].
  + auto=> /> &0 _ _ _ _ _ /(_ (take j (ofbits x{m}))).
    rewrite (take_nth witness).
    + by rewrite size_bits.
    move=> + + ->.
    by rewrite !domE=> /= <-.
  + auto; symmetry; rnd (extract x0) (fun g=> act g x0).
    auto=> /> &1 &2 B_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj x_notin_yqs.
    split=> [g _|_]; 1:exact: extractUniq.
    split=> [g _|_ r _]; 1:exact: sample_dR_iso.
    rewrite extractP !get_set_sameE /=.
    do! split=> p.
    + rewrite mem_set=> - [/domR_size | ->] //.
      by rewrite size_take [smt(size_bits)].
    + rewrite mem_set=> - [/domLx_size | ->] //.
      by rewrite size_take [smt(size_bits)].
    + rewrite (take_nth witness) 1:size_bits // xj !get_setE.
      case (rcons p true = rcons (take j (ofbits x{1})) false)=> />.
      + by move=> /rconsIs.
      move=> _.
      exact valLRy.
    rewrite (take_nth witness) 1:size_bits // xj !get_setE.
    case (p = take j (ofbits x{1}))=> //.
    case (rcons p false = rcons (take j (ofbits x{1})) false)=> //.
      + by rewrite -!cats1=> /catIs.
    move=> _ _.
    exact valLRx.
  + auto=> /> &1 Hj_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj + _ _.
    by rewrite (take_nth witness) 1:size_bits // xj !domE -valLRx.
  auto=> /> &1 &2 B_gis_size domR_size domLy_size domLx_size valLRy valLRx c_le_q xj x_in_yqs _ _.
  congr; congr.
  by rewrite valLRx (take_nth witness) 1:size_bits // xj.
inline *.
sp; wp.
rnd.
auto=> /> &2 z_le_q g _.
split.
+ smt().
move=> _ gis gis_in.
split.
+ smt().
move=> _.
split; 1:apply (supp_dlist_size sample); smt(mem_empty emptyE).
qed.

local equiv H0_BjR:
   Hj(LG0).run ~ Bj(XY_Real).distinguish:
     ={glob D, Q} /\ i{1} = 0 /\ J{2} = 0 /\ 0 <= Q{1}
     ==> ={res}.
proof.
proc=> //=.
inline *.
swap {2} 1 5.
call (:   ={j, c, q}(Hj, Bj) /\ Hj.j{1} = 0
      /\ (() \notin G0.m{1} <=> [] \notin XY_Real.m{2})
      /\ (Hj.gis{1} = (XY_Real.g :: Bj.gis){2})
      /\ size Bj.gis{2} = l - 1
      /\ (() \in G0.m{1} => act (oget G0.m.[()]{1}) x0 = (oget XY_Real.m.[[]]).`1{2})
      /\ (() \in G0.m{1} => act XY_Real.g{2} (act (oget G0.m.[()]{1}) x0) = (oget XY_Real.m.[[]]).`2{2})).
+ proc; inline *; sp; if; auto=> />.
  rcondt {1} 1; 1:by auto=> />.
  sp; if {2}=> />.
  + rcondt {1} 2; 1:auto=> /> &2.
    + case (x0{2})=> + _ _ _ _ + _ _.
      by rewrite take0=> ->.
    wp; symmetry; rnd (extract x0) (fun g=> act g x0).
    skip=> /> &1 &2 dom_eqv size_Bj_gis val_eq1 val_eq2 c_le_q e_notin_m.
    split=> [g _|_]; 1:exact: extractUniq.
    split=> [g _|_ r _]; 1:exact: sample_dR_iso.
    case (x0{2}).
    rewrite !domE take0 !get_set_sameE !extractP drop0 /=.
    case {-1}(ofbits x{1}) (eq_refl (ofbits x{1}))=> />.
    + move=> /= /(congr1 size).
      rewrite size_bits /=.
      smt(gt0_l).
    move=> x1 l.
    rewrite drop0 !extractP.
    by case x1=> />.
  rcondf {1} 2; 1:auto=> /> &2.
  + case (x0{2})=> + _ _ _ _ + _ _.
    by rewrite take0=> ->.
  auto=> /> &1 &2 dom_eqv size_Bj_gis val_eq1 val_eq2 c_le_q.
  case (x0{1}).
  rewrite take0 drop0=> e_in g gin.
  split.
  + case {-1}(ofbits x{2}) (eq_refl (ofbits x{2}))=> />.
    + move=> /= /(congr1 size).
      rewrite size_bits /=.
      smt(gt0_l).
    move=> x1 l.
    rewrite drop0.
    rewrite -dom_eqv in e_in.
    case x1=> />.
    + by rewrite (val_eq2 e_in).
    by rewrite (val_eq1 e_in).
  by rewrite dom_eqv.
sp; wp.
conseq />.
transitivity {2}
  {Bj.gis <@ SampleCons.sample(l);}
  (Hj.j{1} = 0 ==> ={gis}(Hj, Bj))
  (Bj.j{2} = 0 ==> size Bj.gis{2} = l - 1 /\ Bj.gis{1} = (XY_Real.g :: Bj.gis){2})=> />; 1:smt(emptyE mem_empty); first last.
+ inline *; auto=> /> gis + _ _.
  apply supp_dlist_size.
  smt(gt0_l).
transitivity {2}
    {Bj.gis <@ Sample.sample(l);}
    (Hj.j{1} = 0 ==> ={gis}(Hj, Bj))
    (true ==> ={Bj.gis})=> //; last by call Sample_SampleCons_eq; auto=> />; smt(gt0_l).
by inline *; auto=> />.
qed.

local lemma Hj_BjR (j : int):
  0 < j < l =>
  equiv[Hj(LG0).run ~ Bj(XY_Real).distinguish:
    ={glob D, Q} /\ i{1} = j /\ J{2} = j /\ 0 <= Q{1}
    ==> ={res}].
proof.
move=> z_lt_j_lt_l.
proc=> //=.
inline *.
swap {2} 1 5.
call (:   ={j, c, q}(Hj, Bj) /\ Hj.j{1} = j
      /\ (Hj.gis{1} = (XY_Real.g :: Bj.gis){2})
      /\ size Bj.gis{2} = l - j - 1
      /\ (forall (p : bool list), p \in Hj.yqs{1} <=> p \in XY_Real.m{2})
      /\ (forall (p : bool list), p \in Hj.yqs{1} => oget Hj.yqs.[p]{1} = (oget XY_Real.m.[p]{2}).`1)
      /\ (forall (p : bool list), p \in Hj.yqs{1} => act XY_Real.g{2} (oget Hj.yqs.[p]{1}) = (oget XY_Real.m.[p]{2}).`2)).
+ proc; inline *; sp; if; auto=> //.
  rcondf {1} 1.
  + auto=> /> &2 -> /#.
  sp; if=> //.
  + move=> &1 &2 /> _ eqv _.
    by rewrite (eqv _).
  + wp; symmetry; rnd (extract x0) (fun g=> act g x0).
    skip=> /> &1 &2 size_Bj_gis dom_eqv val_eq1 val_eq2 c_le_q e_notin_m.
    split=> [g _|_]; 1:exact: extractUniq.
    split=> [g _|_ r _]; 1:exact: sample_dR_iso.
    rewrite !extractP get_set_sameE /=.
    split; first last.
    + split.
      + move=> p.
        rewrite !domE !get_setE.
        case (p = take j (ofbits x{1}))=> />.
        by rewrite -!domE (dom_eqv p).
      split.
      + move=> p.
        rewrite !domE !get_setE.
        case (p = take j (ofbits x{1}))=> />.
        rewrite -!domE=> _.
        exact val_eq1.
      move=> p.
      rewrite !domE !get_setE.
      case (p = take j (ofbits x{1}))=> />.
      rewrite -!domE=> _.
      exact val_eq2.
    case {-1}(ofbits x{1}) (eq_refl (ofbits x{1}))=> />.
    + move=> /= /(congr1 size).
      rewrite size_bits /=.
      smt(gt0_l).
    move=> x1 p'.
    case {-1}(j <= 0) (eq_refl (j <= 0))=> />; first smt.
    move=> _.
    case {-1}(j = 0) (eq_refl (j = 0))=> />; first smt.
    move=> _.
    case {-1}(j + 1 <= 0) (eq_refl (j + 1 <= 0))=> />; first smt.
    move=> _ use.
    rewrite get_set_sameE (drop_nth witness) /=.
    + move: use.
      move=> /(congr1 size).
      rewrite size_bits -cat1s size_cat /#.
    by case (nth witness p' (j - 1))=> />.
  auto=> /> &1 &2 size_Bj_gis dom_eqv val_eq1 val_eq2 c_le_q.
  case {-1}(ofbits x{2}) (eq_refl (ofbits x{2}))=> />.
  + move=> /= /(congr1 size).
    rewrite size_bits /=.
    smt(gt0_l).
  move=> x1 p'.
  case {-1}(j <= 0) (eq_refl (j <= 0))=> />; first smt.
  case {-1}(j = 0) (eq_refl (j = 0))=> />; first smt.
  case {-1}(j + 1 <= 0) (eq_refl (j + 1 <= 0))=> />; first smt.
  move=> _ _ _ use.
  rewrite (drop_nth witness) /=.
  + move: use.
    move=> /(congr1 size).
    rewrite size_bits -cat1s size_cat /#.
  case (nth witness p' (j - 1))=> /> _ p_in.
  + by rewrite val_eq2.
  by rewrite val_eq1.
sp; wp.
conseq />.
+ smt(mem_empty emptyE).
  (* Transitivity argument with samplecons *)
transitivity {2}
  {Bj.gis <@ SampleCons.sample(l - j);}
  (Hj.j{1} = j /\ i{1} = j ==> i{1} = j /\ ={gis}(Hj, Bj))
  (Bj.j{2} = j ==> size Bj.gis{2} = l - j - 1 /\ Bj.gis{1} = (XY_Real.g :: Bj.gis){2})=> />; 1:smt(emptyE mem_empty); first last.
+ inline *; auto=> /> gis + _ _.
  apply supp_dlist_size.
  smt(gt0_l).
transitivity {2}
    {Bj.gis <@ Sample.sample(l - j);}
    (Hj.j{1} = j ==> ={gis}(Hj, Bj))
    (true ==> ={Bj.gis})=> //; last by call Sample_SampleCons_eq; auto=> />; smt(gt0_l).
by inline *; auto=> />.
qed.

end section PRF_Security.

(** FIXME: WP_IND expects a WP adversary, but we provide it something that distinguishes PROMs
lemma Security (D <: Distinguisher{PRF, RF, WP_Ideal, WP_Real, BoundPRF, Hybrid_PRF_0, Hybrid_PRF_0', Hybrid_PRF_L', Bj, Hybrid_PRF_L, Hybrid_WP_Ideal, Hybrid_WP_Real}) &m (x : int):
    `| Pr[Bounded_PRF_IND(BoundPRF(PRF), D).main(x) @ &m: res] - Pr[Bounded_PRF_IND(BoundPRF(RF), D).main(x) @ &m: res] |
    <= `| Pr[WP_IND(WP_Real, Bj(D)).main() @ &m: res] - Pr[WP_IND(WP_Ideal, B(D)).main() @ &m: res] |.
proof.
admitted.
**)
