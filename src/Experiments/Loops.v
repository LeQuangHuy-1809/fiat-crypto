Require Import Coq.Lists.List.
Require Import Lia. 
Require Import Crypto.Util.Tactics.UniquePose.
Require Import Crypto.Util.Tactics.BreakMatch.
Require Import Crypto.Util.Tactics.DestructHead.
Require Import Crypto.Util.Tactics.SpecializeBy.
Require Import Crypto.Util.Decidable.
Require Import Crypto.Util.Prod.
Require Import Crypto.Util.Option.
Require Import Crypto.Util.Sum.
Require Import Crypto.Util.LetIn.

Require Import Crypto.Util.CPSNotations.

(* TODO: do we have these anywhere? 
Ltac forward H :=
  match type of H with
  | ?A -> ?B => let HA := fresh in assert A as HA; [|specialize(H HA)]
  end.
Ltac forward_by H t :=
  match type of H with
  | ?A -> ?B => let HA := fresh in assert A as HA by t; [|specialize(H HA)]
  end.
 *)

Section Loops.
  Context {A B : Type} (body : A -> A + B).

  Definition loop (fuel : nat) (s : A) : A + B :=
    nat_rect _ (inl s)
             (fun _ s =>
                match s with
                | inl a => body a
                | inr b => s
                end
             ) fuel.

  Context (body_cps : A ~> A + B).
(* WHY does the following not work?
Set Printing Universes.
Check (nat_rect (fun _ => forall R, (A+B -> R)->R)
                (fun R ret => ret (inl s))
                (fun _ recurse =>
                   recurse (forall R, (A + B -> R) -> R)
                           (fun s R ret =>
                              match s with
                              | inl a =>
                                s' <- body_cps a;
                                ret s'
                              | inr b => ret (inr b)
                              end
                ))
                fuel).
The term
 "recurse (~> A + B)
    (fun (s : A + B) (R : Type@{Top.1376}) (ret : A + B -> R) =>
     match s with
     | inl a => s' <- body_cps a;
                ret s'
     | inr b => ret (inr b)
     end)" has type "forall (R : Type@{Top.1376}) (_ : forall _ : sum A B, R), R"
while it is expected to have type
 "forall (R : Type@{Top.1374}) (_ : forall _ : sum A B, R), R"
(universe inconsistency: Cannot enforce Top.1374 <= Top.1376 because Top.1376
< Top.1375 <= Top.1374). *)
  Definition loop_cps (fuel : nat) (s : A) : ~> A+B :=
    nat_rect (fun _ => forall R, (A + B -> R) -> R)
             (fun R ret => ret (inl s))
             (fun _ recurse R =>
                recurse ((A + B -> R) -> R)
                        (fun s ret =>
                           match s with
                           | inl a =>
                             s' <- body_cps a;
                               ret s'
                           | inr b => ret (inr b)
                           end
             )) fuel.

  Context (body_cps_ok : forall s {R} f, body_cps s R f = f (body s)).
  Lemma loop_cps_ok n s {R} f : loop_cps n s R f = f (loop n s).
  Proof.
    revert f; revert R; revert s; induction n; [reflexivity|].
    simpl loop; simpl loop_cps; intros. (* FIXME: unsimpl *)
    rewrite IHn; break_match; [|reflexivity].
    cbv [cpscall]; rewrite body_cps_ok; reflexivity.
  Qed.

  Context (body_cps2 : A -> forall {R}, (A -> R) -> (B -> R) -> R).
  Definition loop_cps2 (fuel : nat) (s : A) :
    forall {R} (timeout : A -> R) (ret : B -> R), R :=
    nat_rect (fun _ => forall R, (A -> R) -> (B -> R) -> R)
             (fun R continue break => continue s)
             (fun _ recurse R continue break =>
                recurse R (fun a => body_cps2 a R continue break) break
             )
             fuel.

  Context (body_cps2_ok : forall s {R} continue break,
              body_cps2 s R continue break =
              match body s with
              | inl a => continue a
              | inr b => break b
              end).
  Lemma loop_cps2_ok n s {R} timeout ret :
    @loop_cps2 n s R timeout ret =
    match loop n s with
    | inl a => timeout a
    | inr b => ret b
    end.
  Proof.
    revert ret; revert timeout; revert R; revert s; induction n;
      [intros; reflexivity|].
    simpl loop; simpl loop_cps2; intros. (* FIXME: unsimpl *)
    repeat (rewrite IHn || rewrite body_cps2_ok || break_match || congruence).
  Qed.

  Lemma loop_fuel_0 s : loop 0 s = inl s.
  Proof. reflexivity. Qed.

  Lemma loop_fuel_S_last n s : loop (S n) s =
                          match loop n s with
                          | inl a => body a
                          | inr b => loop n s
                          end.
  Proof. reflexivity. Qed.

  Lemma loop_fuel_S_first n s : loop (S n) s =
                                match body s with
                                | inl a => loop n a
                                | inr b => inr b
                                end.
  Proof.
    revert s; induction n; intros s.
    { break_match; rewrite ?loop_fuel_S_last, ?loop_fuel_0; congruence. }
    { rewrite loop_fuel_S_last, IHn.
      destruct (body s) eqn:?; [rewrite loop_fuel_S_last; reflexivity | reflexivity]. }
  Qed.

  Lemma loop_fuel_S_stable n s b (H : loop n s = inr b) : loop (S n) s = inr b.
  Proof.
    revert H; revert b; revert s; induction n; intros ? ? H.
    { cbn [loop nat_rect] in H. congruence_sum. }
    { rewrite loop_fuel_S_last.
      break_match; congruence_sum; reflexivity. }
  Qed.

  Lemma loop_fuel_add_stable n m s b (H : loop n s = inr b) : loop (m+n) s = inr b.
  Proof.
    induction m; intros.
    { rewrite PeanoNat.Nat.add_0_l. assumption. }
    { rewrite PeanoNat.Nat.add_succ_l.
      erewrite loop_fuel_S_stable; eauto. }
  Qed.

  Lemma loop_fuel_irrelevant n m s bn bm
        (Hn : loop n s = inr bn)
        (Hm : loop m s = inr bm)
    : bn = bm.
  Proof.
    destruct (Compare_dec.le_le_S_dec n m) as [H|H];
      destruct (PeanoNat.Nat.le_exists_sub _ _ H) as [d [? _]]; subst.
    { erewrite loop_fuel_add_stable in Hm by eassumption; congruence. }
    { erewrite loop_fuel_add_stable in Hn.
      { congruence_sum. reflexivity. }
      { erewrite loop_fuel_S_stable by eassumption. congruence. } }
  Qed.

  Lemma by_invariant' (inv P:_->Prop) measure f s0
          (inv_init : inv s0 /\ measure s0 < f)
          (inv_continue : forall s s', body s = inl s' -> inv s -> inv s' /\ measure s' < measure s)
          (inv_break : forall s s', body s = inr s' -> inv s -> P s')
    : match loop f s0 with
      | inl a => False
      | inr s => P s
      end.
  Proof.
    revert dependent s0; induction f; intros; destruct_head'_and.
    { exfalso; lia. }
    { rewrite loop_fuel_S_first.
      destruct (body s0) eqn:Hs0a; [|solve [eauto] ].
      specialize (IHf a).
      destruct (inv_continue s0 a Hs0a ltac:(assumption)).
      specialize_by (split; (auto || lia)); auto. }
  Qed.

  Lemma by_invariant (inv P:_->Prop) measure f s0
          (inv_init : inv s0 /\ measure s0 < f)
          (inv_continue : forall s s', body s = inl s' -> inv s -> inv s' /\ measure s' < measure s)
          (inv_break : forall s s', body s = inr s' -> inv s -> P s')
    : exists b, loop f s0 = inr b /\ P b.
  Proof.
    pose proof (by_invariant' inv P measure f s0);
      specialize_by assumption; break_match_hyps; [contradiction|eauto].
  Qed.

  (* Completeness proof *)

  Definition iterations_required fuel s : option nat :=
    nat_rect _ None
             (fun n r =>
                match r with
                | Some _ => r
                | None =>
                  match loop (S n) s with
                  | inl a => None
                  | inr b => Some (S n)
                  end
                end
             ) fuel.

  Lemma iterations_required_correct fuel s :
    (forall m, iterations_required fuel s = Some m ->
               1 <= m <= fuel /\
      exists b, forall n, (n < m -> exists a, loop n s = inl a) /\ (m <= n -> loop n s = inr b))
      /\
    (iterations_required fuel s = None -> forall n, n <= fuel -> exists a, loop n s = inl a).
  Proof.
    induction fuel; intros.
    { cbn. split; intros; inversion_option.
      replace n with 0 by lia. rewrite loop_fuel_0. eauto. }
    { change (iterations_required (S fuel) s)
        with (match iterations_required fuel s with
              | None => match loop (S fuel) s with
                        | inl _ => None
                        | inr _ => Some (S fuel)
                        end
              | Some _ => iterations_required fuel s
              end) in *.
      destruct (iterations_required fuel s) in *.
      { split; intros; inversion_option; subst.
        destruct (proj1 IHfuel _ eq_refl); split; [lia|assumption]. }
      { destruct (loop (S fuel) s) eqn:HSf; split; intros; inversion_option; subst.
        { intros. destruct (PeanoNat.Nat.eq_dec n (S fuel)); subst; eauto; [].
          assert (n <= fuel) by lia. eapply IHfuel; congruence. }
        { split; [lia|].
          exists b; intros; split; intros.
          { eapply IHfuel; congruence || lia. }
          { eapply PeanoNat.Nat.le_exists_sub in H; destruct H as [?[]]; subst.
            eauto using loop_fuel_add_stable. } } } }
  Qed.

  Lemma iterations_required_step fuel s s' n
        (Hs : iterations_required fuel s = Some n)
        (Hstep : body s = inl s')
    : exists n', iterations_required fuel s' = Some n' /\ n = S n'.
  Proof.
    eapply iterations_required_correct in Hs.
    destruct Hs as [Hn [b Hs]].
    destruct n as [|n]; [pose proof (proj2 (Hs 0) ltac:(lia)) as Hx; inversion Hx|].
    exists n; split; [|reflexivity].
    pose proof (proj2 (Hs (S n)) ltac:(lia)) as H.
    rewrite loop_fuel_S_first, Hstep in H.
    destruct (iterations_required fuel s') as [x|] eqn:Hs' in *; [f_equal|exfalso].
    { eapply iterations_required_correct in Hs'; destruct Hs' as [Hx Hs'].
      destruct Hs' as [b' Hs'].
      destruct (Compare_dec.le_lt_dec n x) as [Hc|Hc].
      { destruct (Compare_dec.le_lt_dec x n) as [Hc'|Hc']; try lia; [].
        destruct (proj1 (Hs' n) Hc'); congruence. }
      { destruct (proj1 (Hs (S x)) ltac:(lia)) as [? HX].
        rewrite loop_fuel_S_first, Hstep in HX.
        pose proof (proj2 (Hs' x) ltac:(lia)).
        congruence. } }
    { eapply iterations_required_correct in Hs'; [|exact (ltac:(lia) : n <= fuel)].
      destruct Hs'.
      congruence. }
  Qed.

  Lemma invariant_complete (P:_->Prop) f s0 b (H:loop f s0 = inr b) (HP:P b)
        : exists inv measure,
          (inv s0 /\ measure s0 < f)
          /\ (forall s s', body s = inl s' -> inv s -> inv s' /\ measure s' < measure s)
          /\ (forall s s', body s = inr s' -> inv s -> P s').
  Proof.
    set (measure f s :=
           match iterations_required f s with
           | None => 0
           | Some s => pred s
           end).
    exists (fun s => match loop (S (measure f s)) s with
                     | inl a => False
                     | inr r => r = b end).
    exists (measure f); split; [ |repeat match goal with |- _ /\ _ => split end..].
    { cbv [measure].
      destruct (iterations_required f s0) eqn:Hs0;
        eapply iterations_required_correct in Hs0;
          [ .. | exact (ltac:(lia):f <= f)]; [|destruct_head'_ex; congruence].
      destruct Hs0 as [? [? Hs0]].
      replace (S (Nat.pred n)) with n by lia.
      pose proof (proj2 (Hs0 n) ltac:(lia)) as HH; rewrite HH.
      split; [exact (loop_fuel_irrelevant _ _ _ _ _ HH H) | lia]. }
    { intros s s' Hstep Hinv.
      destruct (loop (S (measure f s)) s) eqn:Hs; [contradiction|subst].
      cbv [measure] in *.
      destruct (iterations_required f s) eqn:Hs' in *; [|cbv in Hs; congruence].
      destruct (iterations_required_step _ _ s' _ Hs' Hstep) as [? [HA ?]]; subst.
      rewrite HA.
      destruct (proj1 (iterations_required_correct _ _) _ HA) as [? [? [? HE']]].
      pose proof (HE' ltac:(constructor)) as HE; clear HE'.
      split; [|lia].
      replace (S (Nat.pred (S x))) with (S x) in * by lia.
      rewrite loop_fuel_S_first, Hstep in Hs.
      replace (S (Nat.pred x)) with x in * by lia; rewrite HE.
      exact (loop_fuel_irrelevant _ _ _ _ _ HE Hs). }
    { intros s c Hstep Hinv.
      destruct (loop (S (measure f s)) s) eqn:Hs; [contradiction|subst].
      change (loop 1 s = inr c) in Hstep.
      rewrite (loop_fuel_irrelevant _ _ _ _ _ Hstep Hs); exact HP. }
  Qed.

  Lemma invariant_iff f s0 P :
    (exists b, loop f s0 = inr b /\ P b)
    <->
    (exists inv measure,
        (inv s0 /\ measure s0 < f)
        /\ (forall s s', body s = inl s' -> inv s -> inv s' /\ measure s' < measure s)
        /\ (forall s s', body s = inr s' -> inv s -> P s')).
  Proof.
    repeat (intros || split || destruct_head'_ex || destruct_head'_and);
      eauto using invariant_complete, by_invariant.
  Qed.

  Lemma partial_by_invariant P inv f s0
        (inv_init : inv s0)
        (inv_continue : forall s s', body s = inl s' -> inv s -> inv s')
        (inv_break : forall s s', body s = inr s' -> inv s -> P s')
    : match loop f s0 with
      | inl a => inv a
      | inr s => P s
      end.
  Proof.
    induction f.
    { rewrite loop_fuel_0; auto. }
    { rewrite loop_fuel_S_last.
      destruct (loop f s0) eqn:Hn;
        [ destruct (body a) eqn:Ha; eauto | eauto ]. }
  Qed.

  Lemma by_invariant_inr P inv f s0 b (H : loop f s0 = inr b)
          (inv_init : inv s0)
          (inv_continue : forall s s', body s = inl s' -> inv s -> inv s')
          (inv_break : forall s s', body s = inr s' -> inv s -> P s')
      : P b.
  Proof.
    pose proof (partial_by_invariant P inv f s0) as HH.
    rewrite H in HH; eauto.
  Qed.

  Lemma by_invariant_inr_complete (P:_->Prop) f s0 b (Hf : loop f s0 = inr b) (H : P b) :
    exists (inv : A -> Prop),
      inv s0
      /\ (forall s s', body s = inl s' -> inv s -> inv s')
      /\ (forall s s', body s = inr s' -> inv s -> P s').
  Proof.
    exists (fun s => exists n, match loop n s0 with
                               | inl a => a = s
                               | _ => False end).
    repeat split.
    { exists 0. rewrite loop_fuel_0. reflexivity. }
    { intros s s' Hss' [n Hn]. exists (S n).
      destruct (loop n s0) eqn:Hn_; [|contradiction]; subst a; rename Hn_ into Hn.
      rewrite loop_fuel_S_last, Hn, Hss'. reflexivity. }
    { intros s s' Hss' [n Hn].
      destruct (loop n s0) eqn:Hn_; [|contradiction]; subst a; rename Hn_ into Hn.
      assert (loop (S n) s0 = inr s') as HH by
            (rewrite loop_fuel_S_last, Hn, Hss'; reflexivity).
      rewrite (loop_fuel_irrelevant _ _ _ _ _ HH Hf); assumption. }
  Qed.

  Lemma invariant_inr_iff P f s0 b (H : loop f s0 = inr b) :
      P b <->
      (exists (inv : A -> Prop),
          inv s0
          /\ (forall s s', body s = inl s' -> inv s -> inv s')
          /\ (forall s s', body s = inr s' -> inv s -> P s')).
  Proof.
    split.
    { intros; eapply by_invariant_inr_complete; eauto. }
    { intros [? [?[]]]; eapply by_invariant_inr; eauto. }
  Qed.

  (*
WIP WIP
  
  Fixpoint loop' (fuel : nat) (s : A) {struct fuel} : A + B :=
    match fuel with
    | O => inl s
    | S fuel' =>
      match body s with
      | inl s => loop' fuel' s
      | inr b => inr b
      end end.

  Fixpoint loop'_cps (fuel : nat) (s : A) {struct fuel} : ~> A + B :=
    match fuel with
    | O => return (inl s)
    | S fuel' =>
      s_b <- body_cps s;
        match s_b with
        | inl s => loop'_cps fuel' s
        | inr b => return (inr b)
        end
    end.
    
  
  Lemma loop_break_step fuel start state :
    (body start = inl state) ->
    loop fuel start = inr state.
  Proof.
    destruct fuel; simpl loop; break_match; intros; congruence.
  Qed.

  Lemma loop_continue_step fuel start state :
    (body start = inr state) ->
    loop fuel start =
    match fuel with | O => inl state | S fuel' => loop fuel' state end.
  Proof.
    destruct fuel; simpl loop; break_match; intros; congruence.
  Qed.

  (* TODO: provide [invariant state] to proofs of this *)
  Definition progress (measure : continue_state -> nat) :=
    forall state state', body state = inr state' -> measure state' < measure state.
  Definition terminates fuel start := forall l, loop fuel start <> inl l.
  Lemma terminates_by_measure measure (H : progress measure) :
    forall fuel start, measure start <= fuel -> terminates fuel start.
  Proof.
    induction fuel; intros;
      repeat match goal with
             | _ => solve [ congruence | lia ]
             | _ => progress cbv [progress terminates] in *
             | _ => progress cbn [loop]
             | _ => progress break_match
             | H : forall _ _, body _ = inr _ -> _ , Heq : body _ = inr _ |- _ => specialize (H _ _ Heq)
             | _ => eapply IHfuel
    end.
  Qed.

  Definition loop_default fuel start default
    : break_state :=
    sum_rect
      (fun _ => break_state)
      (fun _ => default)
      (fun result => result)
      (loop fuel start).

  Lemma loop_default_eq fuel start default
        (Hterm : terminates fuel start) :
    loop fuel start = inr (loop_default fuel start default).
  Proof.
    cbv [terminates loop_default sum_rect] in *; break_match; congruence.
  Qed.
End Loops.

Definition by_invariant {continue_state break_state body fuel start default}
           invariant measure P invariant_start invariant_continue invariant_break le_start progress 
  := proj2 (@invariant_iff continue_state break_state body fuel start default (terminates_by_measure body measure progress fuel start le_start) P)
           (ex_intro _ invariant (conj invariant_start (conj invariant_continue invariant_break))).
Arguments terminates_by_measure {_ _ _}.
                 
Module while.
  Section While.
    Context {state}
            (test : state -> bool)
            (body : state -> state).

    Fixpoint while (fuel: nat) (s : state) {struct fuel} : state :=
      if test s
      then
        let s := body s in
        match fuel with
        | O => s
        | S fuel' => while fuel' s
        end
      else s.

    Section AsLoop.
      Local Definition lbody := fun s => if test s then inr (body s) else inl s.

      Lemma eq_loop : forall fuel start, while fuel start = loop_default lbody fuel start (while fuel start).
      Proof.
        induction fuel; intros;
          cbv [lbody loop_default sum_rect id] in *;
          cbn [while loop]; [|rewrite IHfuel]; break_match; auto.
      Qed.

      Lemma by_invariant fuel start 
            (invariant : state -> Prop) (measure : state -> nat) (P : state -> Prop)
            (_: invariant start)
            (_: forall s, invariant s -> if test s then invariant (body s) else P s)
            (_: measure start <= fuel)
            (_: forall s, if test s then measure (body s) < measure s else True)
        : P (while fuel start).
      Proof.
        rewrite eq_loop; cbv [lbody].
        eapply (by_invariant invariant measure);
          repeat match goal with
                 | [ H : forall s, invariant s -> _, G: invariant ?s |- _ ] => unique pose proof (H _ G)
                 | [ H : forall s, if ?f s then _ else _, G: ?f ?s = _ |- _ ] => unique pose proof (H s)
                 | _ => solve [ trivial | congruence ]
                 | _ => progress cbv [progress]
                 | _ => progress intros
                 | _ => progress subst
                 | _ => progress inversion_sum
                 | _ => progress break_match_hyps (* FIXME: this must be last? *)
                 end.
      Qed.
    End AsLoop.
  End While.
  Arguments by_invariant {_ _ _ _ _}.
End while.
Notation while := while.while.

Definition for2 {state} (test : state -> bool) (increment body : state -> state)
  := while test (fun s => increment (body s)). 

Definition for3 {state} init test increment body fuel :=
  @for2 state test increment body fuel init.
*)