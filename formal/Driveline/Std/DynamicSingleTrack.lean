import Driveline.Std.KinematicBicycle
import Driveline.VehicleSpec
import Driveline.SteadyState
import Driveline.AxleLoad

/-!
# `DynamicSingleTrack` (spec §17.5, 17:114-117)

The derivatives of step 2 in both regimes, the reset after step 4, and the reported
`a_lon`. F_z, μ and the heading rule are step inputs taken from the `SurfaceSlice`.
-/

namespace Driveline.Std

/-- The parameters of one `DynamicSingleTrack` step (17:114): the geometry, mass and
cornering stiffnesses of §3, the axle means μ_f, μ_r and `mu_mean` μ̄ of the slice, the
static axle loads F_zf, F_zr of §6.2 after the heading rule, and g. -/
structure DSTP where
  L : ℝ
  lf : ℝ
  lr : ℝ
  m : ℝ
  Izz : ℝ
  Cf : ℝ
  Cr : ℝ
  μf : ℝ
  μr : ℝ
  μbar : ℝ
  Fzf : ℝ
  Fzr : ℝ
  g : ℝ

/-- 17:115 'α_f = δ − arctan((v_y + l_f r)/v_x)' -/
noncomputable def slipF (lf vx vy r δ : ℝ) : ℝ := δ - Real.arctan ((vy + lf * r) / vx)
/-- 17:115 'α_r = −arctan((v_y − l_r r)/v_x)' -/
noncomputable def slipR (lr vx vy r : ℝ) : ℝ := -Real.arctan ((vy - lr * r) / vx)
/-- 17:115 'F_yi = clamp(C_αi α_i, ±μ_i max(0, F_zi))' -/
noncomputable def Fy (C α μ Fz : ℝ) : ℝ := clampS (C * α) (μ * max 0 Fz)

/-- The state of 17:114: the pose, v_x, the CG lateral velocity v_y, the yaw rate r,
δ and a. -/
structure DS where
  X : ℝ
  Y : ℝ
  ψ : ℝ
  vx : ℝ
  vy : ℝ
  r : ℝ
  δ : ℝ
  a : ℝ

/-- The derivatives of step 2 (17:98). -/
structure DDeriv where
  Xd : ℝ
  Yd : ℝ
  ψd : ℝ
  vxDot : ℝ
  vyDot : ℝ
  rDot : ℝ

/-- Step 2 at the state of tick t with the updated δ and a. For v_x ≥ 1 m/s, 17:115-117
'v̇_y = (F_yf + F_yr)/m − v_x r, ṙ = (l_f F_yf − l_r F_yr)/I_zz, v̇_x = clamp(a, ±μ̄g)',
'v_lat = v_y − l_r r', 'Ẋ = v_x cos ψ − v_lat sin ψ, Ẏ = v_x sin ψ + v_lat cos ψ, ψ̇ = r'.
For v_x < 1 m/s, 17:117 'step 2 uses the `KinematicBicycle` equations with
v̇ = clamp(a, ±μ̄g)'; v_y and r are then overwritten by the reset (`dstReset`), so their
rates are taken as 0. -/
noncomputable def dstDeriv (p : DSTP) (s : DS) (δ a : ℝ) : DDeriv :=
  if 1 ≤ s.vx then
    let Ff := Fy p.Cf (slipF p.lf s.vx s.vy s.r δ) p.μf p.Fzf
    let Fr := Fy p.Cr (slipR p.lr s.vx s.vy s.r) p.μr p.Fzr
    let vlat := s.vy - p.lr * s.r
    { Xd := s.vx * Real.cos s.ψ - vlat * Real.sin s.ψ
      Yd := s.vx * Real.sin s.ψ + vlat * Real.cos s.ψ
      ψd := s.r
      vxDot := clampS a (p.μbar * p.g)
      vyDot := (Ff + Fr) / p.m - s.vx * s.r
      rDot := (p.lf * Ff - p.lr * Fr) / p.Izz }
  else
    { Xd := s.vx * Real.cos s.ψ
      Yd := s.vx * Real.sin s.ψ
      ψd := s.vx / p.L * Real.tan δ
      vxDot := clampS a (p.μbar * p.g)
      vyDot := 0
      rDot := 0 }

/-- 17:117 'After step 4, if v_x at tick t or the new v_x is below 1 m/s, the component
sets r = v_x tan δ / L and v_y = l_r r from the new v_x and δ.' -/
noncomputable def dstReset (p : DSTP) (vxOld : ℝ) (s : DS) : DS :=
  if vxOld < 1 ∨ s.vx < 1 then
    let r := s.vx * Real.tan s.δ / p.L
    { s with r := r, vy := p.lr * r }
  else s

/-- 17:117 'It reports `a_lon` = v̇_x − v_lat r'. -/
def dynALon (vxDot vlat r : ℝ) : ℝ := vxDot - vlat * r

/-- 17:104 'a from v̇_lon = `chassis_state.a_lon` + v_lat ψ̇'. -/
def initA (aLon vlat ψdot : ℝ) : ℝ := aLon + vlat * ψdot

/-- The step parameters of a vehicle spec on a road of grade θ and bank φ with friction μ
at every corner (so μ_f = μ_r = μ̄ = μ), for an actor that faces its lane's driving
direction (the heading rule of §6.2 does not negate the loads). -/
noncomputable def dstpOf (t0 : VehicleSpec.Tier0) (t1 : VehicleSpec.Tier1) (μ θ φ : ℝ) :
    DSTP :=
  { L := t0.wheelbase, lf := t1.cg_dist_front, lr := t1.cg_dist_rear, m := t1.mass,
    Izz := t1.inertia_zz, Cf := t1.cornering_stiffness_f, Cr := t1.cornering_stiffness_r,
    μf := μ, μr := μ, μbar := μ,
    Fzf := AxleLoad.Fzf (SteadyState.Params.ofSpec t0 t1) θ φ,
    Fzr := AxleLoad.Fzr (SteadyState.Params.ofSpec t0 t1) θ φ, g := SteadyState.gStd }

/-- P17-40. 17:115 'F_yi = clamp(C_αi α_i, ±μ_i max(0, F_zi))'. μ_i is an axle mean of
corner values, and 16:100 'Every μ must be in [0, 2]', so μ_i ≥ 0. -/
theorem tire_force_bound (C α μ Fz : ℝ) (hμ : 0 ≤ μ) : |Fy C α μ Fz| ≤ μ * max 0 Fz :=
  abs_clampS_le _ _ (mul_nonneg hμ (le_max_left _ _))

/-- With both tire forces inside their friction bounds, ṙ is the linear-tire yaw rate. -/
theorem dst_rDot_linear (p : DSTP) (s : DS) (δ a : ℝ) (hv : 1 ≤ s.vx)
    (hf : |p.Cf * slipF p.lf s.vx s.vy s.r δ| ≤ p.μf * max 0 p.Fzf)
    (hr : |p.Cr * slipR p.lr s.vx s.vy s.r| ≤ p.μr * max 0 p.Fzr) :
    (dstDeriv p s δ a).rDot =
      (p.lf * (p.Cf * slipF p.lf s.vx s.vy s.r δ) - p.lr * (p.Cr * slipR p.lr s.vx s.vy s.r)) /
        p.Izz := by
  simp only [dstDeriv, if_pos hv, Fy, clampS_of_abs_le hf, clampS_of_abs_le hr]

theorem tan_small : 0 < Real.tan (3 / 4000) ∧ Real.tan (3 / 4000) ≤ 1 / 1000 := by
  have hpi := Real.pi_gt_three
  refine ⟨Real.tan_pos_of_pos_of_lt_pi_div_two (by norm_num) (by linarith), ?_⟩
  have hs : Real.sin (3 / 4000) ≤ 3 / 4000 := Real.sin_le (by norm_num)
  have hc : 1 - (3 / 4000 : ℝ) ^ 2 / 2 ≤ Real.cos (3 / 4000) := Real.one_sub_sq_div_two_le_cos
  have hc0 : 0 < Real.cos (3 / 4000) := by nlinarith
  rw [Real.tan_eq_sin_div_cos, div_le_iff₀ hc0]
  nlinarith

/-- P17-41, refuted. 17:117 'The front lateral force acts along the body y axis. This
small-angle model matches §8.' With l_f + l_r only within the 03:31 tolerance of L
(`SteadyState.ssWitnessG`, l_r = 3/2 + 10^-7), at a feasible §8 ST state
(v = 10 m/s, psi_dot = 1/100 rad/s, μ = 1 on a flat road) entered by 17:104 with
v_y = v_lat,ra + l_r psi_dot, δ = δ_ss and a = 0, the tire forces are inside their
friction bounds and ṙ ≠ 0. This is the counterexample of P06-23
(`SteadyState.dst_not_balanced_tolerance`) carried over to the clamped tires of 17:115. -/
theorem dst_ss_not_steady : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v r μ : ℝ,
    1 ≤ v ∧ 0 ≤ μ ∧ μ ≤ 2 ∧
    ¬ SteadyState.infeasible (SteadyState.Params.ofSpec s.tier0 t1) μ
      (SteadyState.deltaSS (SteadyState.Params.ofSpec s.tier0 t1) v r) (SteadyState.aY v r) ∧
    ∀ X Y ψ : ℝ,
      let P := SteadyState.Params.ofSpec s.tier0 t1
      let q : DS := ⟨X, Y, ψ, v, SteadyState.vLatRa P v r + P.lr * r, r,
        SteadyState.deltaSS P v r, 0⟩
      (dstDeriv (dstpOf s.tier0 t1 μ 0 0) q (SteadyState.deltaSS P v r) 0).vxDot = 0 ∧
      (dstDeriv (dstpOf s.tier0 t1 μ 0 0) q (SteadyState.deltaSS P v r) 0).rDot ≠ 0 := by
  open SteadyState in
  refine ⟨ssWitnessG, ssWitnessG_wf, ssT1G, rfl, 10, 1 / 100, 1, by norm_num, by norm_num,
    by norm_num, ?_, ?_⟩
  · apply feasible_of_small _ _ _ (by norm_num) <;>
      simp [Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaR, alphaF, Fyf, Fyr, aY,
        abs_le] <;> norm_num
  · intro X Y ψ
    set P := Params.ofSpec ssWitnessG.tier0 ssT1G with hP
    have hpi := Real.pi_gt_three
    have hα : alphaR P 10 (1 / 100) = 3 / 4000 := by
      simp [P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaR, Fyr, aY]; norm_num
    have hG2 : |alphaR P 10 (1 / 100)| < Real.pi / 2 := by
      rw [hα, abs_of_pos (by norm_num)]; linarith
    obtain ⟨hR, hF⟩ := st_slip_reproduced P 10 (1 / 100) (by norm_num)
    rw [arctan_tan_alphaR P 10 (1 / 100) hG2, hα] at hR
    set vy := vLatRa P 10 (1 / 100) + P.lr * (1 / 100)
    set δ := deltaSS P 10 (1 / 100)
    refine ⟨by simp [dstDeriv, clampS, clamp, dstpOf, gStd]; norm_num, ?_⟩
    have eF : slipF ssT1G.cg_dist_front 10 vy (1 / 100) δ = dstAlphaF P 10 vy (1 / 100) δ := rfl
    have eR : slipR ssT1G.cg_dist_rear 10 vy (1 / 100) = dstAlphaR P 10 vy (1 / 100) := rfl
    obtain ⟨t0, t1⟩ := tan_small
    have hvl : vLatRa P 10 (1 / 100) = -10 * Real.tan (3 / 4000) := by
      simp only [vLatRa, hα]
    have hL : P.L = 3 := rfl
    have hlf : P.lf = 3 / 2 := rfl
    have hlr : P.lr = 3 / 2 + 1 / 10 ^ 7 := rfl
    have haf : alphaF P 10 (1 / 100) = 150 * (3 / 2 + 1 / 10 ^ 7) / 3 / 100000 := by
      simp [P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaF, Fyf, aY]; norm_num
    have hx := Real.abs_arctan_le_abs (x := (vLatRa P 10 (1 / 100) + P.L * (1 / 100)) / 10)
    have hy := Real.abs_arctan_le_abs
      (x := (vLatRa P 10 (1 / 100) + (P.lf + P.lr) * (1 / 100)) / 10)
    rw [hvl, hL] at hx
    rw [hvl, hlf, hlr] at hy
    have hx' : |(-10 * Real.tan (3 / 4000) + 3 * (1 / 100)) / 10| ≤ 1 / 100 := by
      rw [abs_le]; constructor <;> linarith
    have hy' : |(-10 * Real.tan (3 / 4000) + (3 / 2 + (3 / 2 + 1 / 10 ^ 7)) * (1 / 100)) / 10|
        ≤ 1 / 100 := by
      rw [abs_le]; constructor <;> norm_num <;> linarith
    have hFz : (6000 : ℝ) ≤ AxleLoad.Fzf P 0 0 ∧ (6000 : ℝ) ≤ AxleLoad.Fzr P 0 0 := by
      simp [AxleLoad.Fzf, AxleLoad.Fzr, P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness,
        gStd]; norm_num
    have hbf : |ssT1G.cornering_stiffness_f * slipF ssT1G.cg_dist_front 10 vy (1 / 100) δ| ≤
        1 * max 0 (AxleLoad.Fzf P 0 0) := by
      rw [eF, hF, haf, show ssT1G.cornering_stiffness_f = 100000 from rfl, abs_mul,
        abs_of_pos (by norm_num : (0 : ℝ) < 100000), one_mul, max_eq_right (by linarith)]
      have := abs_add_le (150 * (3 / 2 + 1 / 10 ^ 7) / 3 / 100000 : ℝ)
        (Real.arctan ((vLatRa P 10 (1 / 100) + P.L * (1 / 100)) / 10) -
          Real.arctan ((vLatRa P 10 (1 / 100) + (P.lf + P.lr) * (1 / 100)) / 10))
      have := abs_sub (Real.arctan ((vLatRa P 10 (1 / 100) + P.L * (1 / 100)) / 10))
        (Real.arctan ((vLatRa P 10 (1 / 100) + (P.lf + P.lr) * (1 / 100)) / 10))
      rw [hvl, hL, hlf, hlr] at *
      rw [abs_of_pos (by norm_num : (0 : ℝ) < 150 * (3 / 2 + 1 / 10 ^ 7) / 3 / 100000)] at *
      linarith
    have hbr : |ssT1G.cornering_stiffness_r * slipR ssT1G.cg_dist_rear 10 vy (1 / 100)| ≤
        1 * max 0 (AxleLoad.Fzr P 0 0) := by
      rw [eR, hR, show ssT1G.cornering_stiffness_r = 100000 from rfl,
        max_eq_right (by linarith), abs_of_pos (by norm_num)]
      linarith
    have hrd := dst_rDot_linear (dstpOf ssWitnessG.tier0 ssT1G 1 0 0)
      ⟨X, Y, ψ, 10, vy, 1 / 100, δ, 0⟩ δ 0 (by norm_num) hbf hbr
    simp only [dstpOf] at hrd ⊢
    rw [hrd]
    obtain ⟨-, h⟩ := dst_residuals P 2500 10 (1 / 100) (by norm_num)
      (by simp [P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness])
      (by simp [P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness]) hG2
    have hI : ssT1G.inertia_zz = 2500 := rfl
    have e : (ssT1G.cg_dist_front * (ssT1G.cornering_stiffness_f *
        slipF ssT1G.cg_dist_front 10 vy (1 / 100) δ) - ssT1G.cg_dist_rear *
        (ssT1G.cornering_stiffness_r * slipR ssT1G.cg_dist_rear 10 vy (1 / 100))) /
        ssT1G.inertia_zz = dstRDot P 2500 10 vy (1 / 100) δ := by
      rw [hI]; rfl
    rw [e, h]
    have hne : Real.arctan ((vLatRa P 10 (1 / 100) + P.L * (1 / 100)) / 10) ≠
        Real.arctan ((vLatRa P 10 (1 / 100) + (P.lf + P.lr) * (1 / 100)) / 10) := by
      intro e
      have := Real.arctan_injective e
      rw [hL, hlf, hlr] at this
      norm_num at this
    have hk : P.lf * P.Caf ≠ 0 := by simp [P, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness]
    exact div_ne_zero (mul_ne_zero hk (sub_ne_zero.mpr hne)) (by norm_num)

/-- P17-42. 17:117 'Explicit Euler is stable only if |1 + λΔt| < 1 for each eigenvalue λ
of the linearized lateral dynamics, that is Δt < 2|Re λ| / |λ|²'. The equivalence holds
with Re λ < 0 added; without it, λ = 1 and Δt = 1 satisfy the bound but not
|1 + λΔt| < 1 (spec gap). -/
theorem euler_stability (z : ℂ) (h : ℝ) (hh : 0 < h) :
    (‖1 + z * h‖ < 1 ↔ z.re < 0 ∧ h < 2 * |z.re| / ‖z‖ ^ 2) ∧
      ((1 : ℝ) < 2 * |(1 : ℂ).re| / ‖(1 : ℂ)‖ ^ 2 ∧ ¬ ‖1 + (1 : ℂ) * (1 : ℝ)‖ < 1) := by
  refine ⟨?_, by norm_num, by norm_num⟩
  have hn : ‖1 + z * h‖ ^ 2 = 1 + h * (2 * z.re + h * ‖z‖ ^ 2) := by
    rw [Complex.sq_norm, Complex.sq_norm, Complex.normSq_apply, Complex.normSq_apply]
    simp; ring
  have key : ‖1 + z * h‖ < 1 ↔ h * ‖z‖ ^ 2 < -2 * z.re := by
    rw [← abs_norm, ← sq_lt_one_iff_abs_lt_one, hn]
    constructor
    · intro hl
      have : h * (2 * z.re + h * ‖z‖ ^ 2) < 0 := by linarith
      by_contra hc
      nlinarith [mul_nonneg hh.le (show 0 ≤ 2 * z.re + h * ‖z‖ ^ 2 by linarith)]
    · intro hl
      nlinarith
  rw [key]
  constructor
  · intro hl
    have hz : 0 ≤ h * ‖z‖ ^ 2 := by positivity
    have hre : z.re < 0 := by linarith
    have hz2 : 0 < ‖z‖ ^ 2 := by
      rcases (eq_or_lt_of_le (sq_nonneg ‖z‖)) with e | e
      · have hz0 : z = 0 := by
          rw [← norm_eq_zero]; exact (pow_eq_zero_iff (n := 2) (by norm_num)).mp e.symm
        simp [hz0] at hre
      · exact e
    refine ⟨hre, ?_⟩
    rw [abs_of_neg hre, lt_div_iff₀ hz2]; linarith
  · rintro ⟨hre, hl⟩
    have hz2 : 0 < ‖z‖ ^ 2 := by
      have : z ≠ 0 := fun e => by simp [e] at hre
      positivity
    rw [abs_of_neg hre, lt_div_iff₀ hz2] at hl; linarith

/-- P17-44. 17:117 'for v_x < 1 m/s, step 2 uses the `KinematicBicycle` equations with
v̇ = clamp(a, ±μ̄g), so the friction limit is the same in both regimes'. -/
theorem friction_both_regimes (p : DSTP) (s : DS) (δ a : ℝ) :
    (dstDeriv p s δ a).vxDot = clampS a (p.μbar * p.g) := by
  unfold dstDeriv; split_ifs <;> rfl

/-- P17-45, refuted. 17:117 'the component sets r = v_x tan δ / L and v_y = l_r r from
the new v_x and δ ... Crossing upward, the reset leaves both slip angles at 0'. After the
reset α_r = −arctan((l_r r − l_r r)/v_x) = 0, but α_f = δ − arctan((l_f + l_r)/L · tan δ)
is 0 only if l_f + l_r = L, and 03:31 accepts l_f + l_r within tolerance of L
(`VehicleSpec.cg_readings_disagree`). Witness: `SteadyState.ssWitnessG`
(l_r = 3/2 + 10^-7, L = 3), crossing upward from v_x = 1/2 to 1 m/s with δ = 1/4 ≤ δ_max. -/
theorem reset_front_slip_nonzero : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1,
    ∃ (q : DS) (vxOld : ℝ), vxOld < 1 ∧ 1 ≤ q.vx ∧ |q.δ| ≤ s.tier0.max_steer_angle ∧
      let q' := dstReset (dstpOf s.tier0 t1 1 0 0) vxOld q
      slipR t1.cg_dist_rear q'.vx q'.vy q'.r = 0 ∧
        slipF t1.cg_dist_front q'.vx q'.vy q'.r q'.δ ≠ 0 := by
  open SteadyState in
  refine ⟨ssWitnessG, ssWitnessG_wf, ssT1G, rfl, ⟨0, 0, 0, 1, 0, 0, 1 / 4, 0⟩, 1 / 2,
    by norm_num, by norm_num, ?_, ?_⟩
  · simp [ssWitnessG, ssWitness, abs_of_pos]; norm_num
  · have hpi := Real.pi_gt_three
    simp only [dstReset, dstpOf, show (1 / 2 : ℝ) < 1 by norm_num, true_or, ite_true]
    refine ⟨by simp [slipR], ?_⟩
    have ht : 0 < Real.tan (1 / 4) :=
      Real.tan_pos_of_pos_of_lt_pi_div_two (by norm_num) (by linarith)
    simp only [slipF, ssWitnessG, ssWitness, ssT1G, ssT1, sub_ne_zero]
    intro e
    have := congrArg Real.tan e
    rw [Real.tan_arctan] at this
    have : Real.tan (1 / 4) * (1 / (3 * 10 ^ 7)) = 0 := by linarith
    norm_num at this
    linarith

/-- P17-46. 17:117 'It reports `a_lon` = v̇_x − v_lat r', and 17:104 sets 'a from
v̇_lon = `chassis_state.a_lon` + v_lat ψ̇': an init from the reported `a_lon` recovers v̇_x. -/
theorem alon_round_trip (vxDot vlat r : ℝ) : initA (dynALon vxDot vlat r) vlat r = vxDot := by
  simp only [initA, dynALon]; ring

end Driveline.Std
