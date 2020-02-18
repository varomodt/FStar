(*
   Copyright 2019 Microsoft Research

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)
module Steel.Actions
open Steel.Memory
open FStar.Real
open Steel.Permissions
module U32 = FStar.UInt32

let depends_only_on_without_affinity (q:heap -> prop) (fp:hprop) =
  (forall (h0:hheap fp) (h1:heap{disjoint h0 h1}). q h0 <==> q (join h0 h1))
let pre_m_action (fp:hprop) (a:Type) (fp':a -> hprop) =
  hmem fp -> (x:a & hmem (fp' x))

let fp_prop (fp:hprop) = q:(heap -> prop){q `depends_only_on_without_affinity` fp}

let ac_reasoning_for_m_frame_preserving
  (p q r:hprop) (m:mem)
: Lemma
  (requires interp ((p `star` q) `star` r) (heap_of_mem m))
  (ensures interp (p `star` r) (heap_of_mem m))
= calc (equiv) {
    (p `star` q) `star` r;
       (equiv) { star_commutative p q;
                 equiv_extensional_on_star (p `star` q) (q `star` p) r }
    (q `star` p) `star` r;
       (equiv) { star_associative q p r }
    q `star` (p `star` r);
  };
  assert (interp (q `star` (p `star` r)) (heap_of_mem m));
  affine_star q (p `star` r) (heap_of_mem m)

val mem_evolves : FStar.Preorder.preorder mem

let is_m_frame_and_preorder_preserving (#a:Type) (#fp:hprop) (#fp':a -> hprop) (f:pre_m_action fp a fp') =
  forall (frame:hprop) (m0:hmem (fp `star` frame)).
    (ac_reasoning_for_m_frame_preserving fp frame (locks_invariant m0) m0;
     let (| x, m1 |) = f m0 in
     interp ((fp' x `star` frame) `star` locks_invariant m1) (heap_of_mem m1) /\
     mem_evolves m0 m1 /\
     (forall (f_frame:fp_prop frame). f_frame (heap_of_mem m0) <==> f_frame (heap_of_mem m1)))

let m_action (fp:hprop) (a:Type) (fp':a -> hprop) =
  f:pre_m_action fp a fp'{ is_m_frame_and_preorder_preserving f }

////////////////////////////////////////////////////////////////////////////////
// Arrays
////////////////////////////////////////////////////////////////////////////////

val as_seq (#t:_) (a:array_ref t) (m:hheap (array a))
  : (Seq.lseq t (U32.v (length a)))

/// as_seq respect pts_to_array
val as_seq_lemma
  (#t:_)
  (a:array_ref t)
  (i:U32.t{U32.v i < U32.v (length a)})
  (p:permission{allows_read p})
  (m:hheap (array_perm a p))
  : Lemma (interp (array a) m /\
           interp (pts_to_array a p (as_seq a m)) m)

val index_array
  (#t:_)
  (a:array_ref t)
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (p: permission{allows_read p})
  (i:U32.t{U32.v i < U32.v (length a)})
  : m_action
    (pts_to_array a p iseq)
    (x:t{x == Seq.index iseq (U32.v i)})
    (fun _ -> pts_to_array a p iseq)

val upd_array
  (#t:_)
  (a:array_ref t)
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (i:U32.t{U32.v i < U32.v (length a)})
  (v: t)
  : m_action
    (pts_to_array a full_permission iseq)
    unit
    (fun _ -> pts_to_array a full_permission (Seq.upd iseq (U32.v i) v))

val alloc_array
  (#t: _)
  (len:U32.t)
  (init: t)
  : m_action
    emp
    (a:array_ref t{length a = len /\ offset a = 0ul /\ max_length a = len})
    (fun a -> pts_to_array a full_permission (Seq.Base.create (U32.v len) init))

val free_array
  (#t: _)
  (a: array_ref t{freeable a})
  : m_action
    (array_perm a full_permission)
    unit
    (fun _ -> emp)

val share_array
  (#t: _)
  (a: array_ref t)
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (p: permission{allows_read p})
  : m_action
    (pts_to_array a p iseq)
    (a':array_ref t{
      length a' = length a /\ offset a' = offset a /\ max_length a' = max_length a /\
      address a = address a'
    })
    (fun a' -> star
      (pts_to_array a (half_permission p) iseq)
      (pts_to_array a' (half_permission p) (Ghost.hide (Ghost.reveal iseq)))
    )

val gather_array
  (#t: _)
  (a: array_ref t)
  (a':array_ref t{
    length a' = length a /\ offset a' = offset a /\ max_length a' = max_length a /\
    address a = address a'
  })
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (p: permission{allows_read p})
  (p': permission{allows_read p' /\ summable_permissions p p'})
  : m_action
    (star
      (pts_to_array a p iseq)
      (pts_to_array a' p' (Ghost.hide (Ghost.reveal iseq)))
    )
    unit
    (fun _ -> pts_to_array a (sum_permissions p p') iseq)

val split_array
  (#t: _)
  (a: array_ref t)
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (p: permission{allows_read p})
  (i:U32.t{U32.v i < U32.v (length a)})
  : m_action
    (pts_to_array a p iseq)
    (as:(array_ref t & array_ref t){(
      length (fst as) = i /\ length (snd as) = U32.sub (length a) i /\
      offset (fst as) = offset a /\ offset (snd as) = U32.add (offset a) i /\
      max_length (fst as) = max_length a /\ max_length (snd as) = max_length a /\
      address (fst as) = address a /\ address (snd as) = address a
    )})
    (fun (a1, a2) -> star
      (pts_to_array a1 p (Seq.slice iseq 0 (U32.v i)))
      (pts_to_array a2 p (Seq.slice iseq (U32.v i) (U32.v (length a))))
    )

val glue_array
  (#t: _)
  (a: array_ref t)
  (a': array_ref t{
    address a = address a' /\ max_length a = max_length a' /\
    offset a' = U32.add (offset a) (length a)
  })
  (iseq: Ghost.erased (Seq.lseq t (U32.v (length a))))
  (iseq': Ghost.erased (Seq.lseq t (U32.v (length a'))))
  (p: permission{allows_read p})
  : m_action
    (star (pts_to_array a p iseq) (pts_to_array a' p iseq'))
    (new_a:array_ref t{
      address new_a = address a /\ max_length new_a = max_length a /\
      offset new_a = offset a /\ length new_a = U32.add (length a) (length a')
    })
    (fun new_a -> pts_to_array new_a p (Seq.Base.append iseq iseq'))

///////////////////////////////////////////////////////////////////////////////
// Utilities
///////////////////////////////////////////////////////////////////////////////

val rewrite_hprop (p:hprop) (p':hprop{p `equiv` p'}) : m_action p unit (fun _ -> p')

///////////////////////////////////////////////////////////////////////////////
// References with preorders
///////////////////////////////////////////////////////////////////////////////

val sel_ref
  (#t: Type0)
  (r: reference t)
  (pre: Ghost.erased (Preorder.preorder t))
  (h: hmem (ref r pre))
  : Tot t

val sel_ref_lemma
  (t: Type0)
  (p: permission{allows_read p})
  (r: reference t)
  (pre: Preorder.preorder t)
  (m: hmem (ref_perm r p pre))
  : Lemma (
    interp (ref r pre `star` locks_invariant m) (heap_of_mem m) /\
    interp (pts_to_ref r p (sel_ref r pre m) pre `star` locks_invariant m) (heap_of_mem m)
  )

val get_ref
  (#t: Type0)
  (r: reference t)
  (p: permission{allows_read p})
  (pre: Ghost.erased (Preorder.preorder t))
  : m_action
    (ref_perm r p pre)
    (x:t)
    (fun x -> pts_to_ref r p x pre)

val set_ref
  (#t: Type0)
  (r: reference t)
  (old_v: Ghost.erased t)
  (v: t)
  (pre: (Ghost.erased (Preorder.preorder t)){(Ghost.reveal pre) old_v v})
  : m_action
    (pts_to_ref r full_permission old_v pre)
    unit
    (fun _ -> pts_to_ref r full_permission v pre)

val alloc_ref
  (#t: Type0)
  (v: t)
  (pre: Ghost.erased (Preorder.preorder t))
  : m_action
    emp
    (reference t)
    (fun r -> pts_to_ref r full_permission v pre)

val free_ref
  (#t: Type0)
  (r: reference t)
  (pre: Ghost.erased (Preorder.preorder t))
  : m_action
    (ref_perm r full_permission pre)
    unit
    (fun _ -> emp)

val share_ref
  (#t: Type0)
  (r: reference t)
  (p: permission{allows_read p})
  (contents: Ghost.erased t)
  (pre: Ghost.erased (Preorder.preorder t))
  : m_action
    (pts_to_ref r p contents pre)
    (r':reference t{ref_address r' = ref_address r})
    (fun r' ->
      pts_to_ref r (half_permission p) contents pre `star`
      pts_to_ref r' (half_permission p) contents pre
    )

val gather_ref
  (#t: Type0)
  (r: reference t)
  (r':reference t{ref_address r' = ref_address r})
  (p: permission{allows_read p})
  (p': permission{allows_read p' /\ summable_permissions p p'})
  (contents: Ghost.erased t)
  (pre: Ghost.erased (Preorder.preorder t))
  : m_action
    (pts_to_ref r p contents pre `star`
      pts_to_ref r' p' contents pre)
    unit
    (fun _ -> pts_to_ref r (sum_permissions p p') contents pre)

///////////////////////////////////////////////////////////////////////////////
// Locks
///////////////////////////////////////////////////////////////////////////////

val lock (p:hprop) : Type0

val new_lock (p:hprop)
  : m_action p (lock p) (fun _ -> emp)

val lock_ok (#p:hprop) (l:lock p) (m:mem) : prop

let pure (p:prop) : hprop = refine emp (fun _ -> p)

val maybe_acquire
  (#p: hprop)
  (l:lock p)
  (m:hmem emp { lock_ok l m } )
  : (b:bool & m:hmem (h_or (pure (b == false)) p))

val release
  (#p: hprop)
  (l:lock p)
  (m:hmem p { lock_ok l m } )
  : (b:bool & hmem emp)
