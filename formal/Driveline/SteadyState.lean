import Mathlib.Analysis.SpecialFunctions.Trigonometric.Arctan
import Mathlib.Analysis.SpecialFunctions.Trigonometric.ArctanDeriv
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Bounds
import Mathlib.Analysis.Calculus.Deriv.Basic
import Mathlib.Analysis.Asymptotics.Defs
import Mathlib.Analysis.Real.Pi.Bounds
import Driveline.VehicleSpec
import Driveline.Angles
import Driveline.InitContext

/-!
# Steady-state cornering solution (§8) and the spawn steady circle (§6.2 Pass 1 step 2)

The §8 solve for the three physics tiers, the §17 `DynamicSingleTrack` lateral
equations with linear tires, and the rear-axle motion on the steady circle.
-/

open Real

namespace Driveline.SteadyState

/-- §8 'g = 9.80665 m/s^2' (08:19) -/
def gStd : ℝ := 9.80665

/-- The Tier 0 and Tier 1 values that the §8 solve reads. -/
structure Params where
  L : ℝ
  lf : ℝ
  lr : ℝ
  m : ℝ
  Caf : ℝ
  Car : ℝ
  hcg : ℝ
  δmax : ℝ

/-- The parameters of a vehicle spec (03:20-21). -/
def Params.ofSpec (t0 : VehicleSpec.Tier0) (t1 : VehicleSpec.Tier1) : Params :=
  ⟨t0.wheelbase, t1.cg_dist_front, t1.cg_dist_rear, t1.mass, t1.cornering_stiffness_f,
    t1.cornering_stiffness_r, t1.cg_height, t0.max_steer_angle⟩

inductive Tier | ks | st | mb deriving DecidableEq

/-- 08:12 'The lateral acceleration is a_y = v psi_dot.' -/
def aY (v r : ℝ) : ℝ := v * r
/-- 08:14 'δ_KS = arctan(L psi_dot / v)' -/
noncomputable def deltaKS (L v r : ℝ) : ℝ := arctan (L * r / v)
/-- 08:16 'F_yf = m a_y l_r/L' -/
noncomputable def Fyf (p : Params) (v r : ℝ) : ℝ := p.m * aY v r * p.lr / p.L
/-- 08:16 'F_yr = m a_y l_f/L' -/
noncomputable def Fyr (p : Params) (v r : ℝ) : ℝ := p.m * aY v r * p.lf / p.L
/-- 08:16 'α_f = F_yf / C_αf' -/
noncomputable def alphaF (p : Params) (v r : ℝ) : ℝ := Fyf p v r / p.Caf
/-- 08:16 'α_r = F_yr / C_αr' -/
noncomputable def alphaR (p : Params) (v r : ℝ) : ℝ := Fyr p v r / p.Car
/-- 08:17 'v_lat,ra = −v tan α_r' -/
noncomputable def vLatRa (p : Params) (v r : ℝ) : ℝ := -v * tan (alphaR p v r)
/-- 08:17 'δ_ss = α_f + arctan((v_lat,ra + L psi_dot)/v)' -/
noncomputable def deltaSS (p : Params) (v r : ℝ) : ℝ :=
  alphaF p v r + arctan ((vLatRa p v r + p.L * r) / v)
/-- 08:17 'β_cg = arctan((v_lat,ra + l_r psi_dot)/v)' -/
noncomputable def betaCG (p : Params) (v r : ℝ) : ℝ := arctan ((vLatRa p v r + p.lr * r) / v)
/-- 06:96 'K_us = m/L (l_r/C_αf − l_f/C_αr)' -/
noncomputable def Kus (p : Params) : ℝ := p.m / p.L * (p.lr / p.Caf - p.lf / p.Car)

structure SS where
  vLat : ℝ
  delta : ℝ

/-- The two callers of the §8 solve (08:14): cold init, with the spawn curvature κ_0 of
§6.2, and a promotion or demotion, with the committed `front_wheel_angle`. -/
inductive Phase
  | cold (κ0 : ℝ)
  | window (δkept : ℝ)

/-- 08:14 'δ_ss = δ_KS = arctan(L psi_dot / v) for v ≠ 0. When v = 0 ... cold init uses
δ_ss = arctan(L κ0) with the spawn curvature of §6.2, and a promotion or demotion at any
v < 1.0 m/s keeps the committed front_wheel_angle instead of the formula' -/
noncomputable def deltaLow (L v r : ℝ) : Phase → ℝ
  | .cold κ0 => if v = 0 then arctan (L * κ0) else deltaKS L v r
  | .window δkept => if v < 1 then δkept else deltaKS L v r

/-- §8 tier dispatch (08:14-17): the kinematic solution for `KS` and for every tier at
v < 1 m/s, and the linear-tire `ST` solution otherwise. -/
noncomputable def solve (t : Tier) (p : Params) (ph : Phase) (v r : ℝ) : SS :=
  if t = .ks ∨ v < 1 then ⟨0, deltaLow p.L v r ph⟩ else ⟨vLatRa p v r, deltaSS p v r⟩

/-- 08:19 'infeasible if |δ_ss| > δ_max, or if |a_y| > μ g' -/
def infeasible (p : Params) (μ δ ay : ℝ) : Prop := p.δmax < |δ| ∨ μ * gStd < |ay|

/-! §17 `DynamicSingleTrack` lateral part with linear (unclamped) tires (17:115-116). -/

noncomputable def dstAlphaF (p : Params) (vx vy r δ : ℝ) : ℝ := δ - arctan ((vy + p.lf * r) / vx)
noncomputable def dstAlphaR (p : Params) (vx vy r : ℝ) : ℝ := -arctan ((vy - p.lr * r) / vx)
noncomputable def dstVyDot (p : Params) (vx vy r δ : ℝ) : ℝ :=
  (p.Caf * dstAlphaF p vx vy r δ + p.Car * dstAlphaR p vx vy r) / p.m - vx * r
noncomputable def dstRDot (p : Params) (Izz vx vy r δ : ℝ) : ℝ :=
  (p.lf * (p.Caf * dstAlphaF p vx vy r δ) - p.lr * (p.Car * dstAlphaR p vx vy r)) / Izz

/-! The steady circle: body velocity (v, vl) at the rear axle, yaw ψ0 + r t. -/

/-- World velocity of the rear axle on the steady circle. -/
noncomputable def circVel (ψ0 r v vl t : ℝ) : ℝ × ℝ :=
  (v * cos (ψ0 + r * t) - vl * sin (ψ0 + r * t), v * sin (ψ0 + r * t) + vl * cos (ψ0 + r * t))
/-- A world vector in the heading frame of yaw ψ. -/
noncomputable def toBody (ψ : ℝ) (w : ℝ × ℝ) : ℝ × ℝ :=
  (w.1 * cos ψ + w.2 * sin ψ, -w.1 * sin ψ + w.2 * cos ψ)
/-- Curvature of the rear-axle path on the steady circle. -/
noncomputable def rearCurv (v vl r : ℝ) : ℝ := r / sqrt (v ^ 2 + vl ^ 2)

/-! ## The steady circle -/

/-- The acceleration of the rear axle on the steady circle. -/
theorem circVel_deriv (ψ0 r v vl t : ℝ) :
    HasDerivAt (fun s => (circVel ψ0 r v vl s).1)
      (-(v * r) * sin (ψ0 + r * t) - vl * r * cos (ψ0 + r * t)) t ∧
    HasDerivAt (fun s => (circVel ψ0 r v vl s).2)
      (v * r * cos (ψ0 + r * t) - vl * r * sin (ψ0 + r * t)) t := by
  have hθ : HasDerivAt (fun s => ψ0 + r * s) r t := by
    simpa using ((hasDerivAt_id t).const_mul r).const_add ψ0
  constructor
  · exact (((hθ.cos).const_mul v).sub ((hθ.sin).const_mul vl)).congr_deriv (by ring)
  · exact (((hθ.sin).const_mul v).add ((hθ.cos).const_mul vl)).congr_deriv (by ring)

/-- P06-12 06:78 'a_lon = −v_lat,ra psi_dot_0': the body-x component of the rear-axle
acceleration on the steady circle. -/
theorem steady_circle_a_lon (ψ0 r v vl t : ℝ) : ∃ a : ℝ × ℝ,
    HasDerivAt (fun s => (circVel ψ0 r v vl s).1) a.1 t ∧
    HasDerivAt (fun s => (circVel ψ0 r v vl s).2) a.2 t ∧
    (toBody (ψ0 + r * t) a).1 = -vl * r := by
  obtain ⟨h1, h2⟩ := circVel_deriv ψ0 r v vl t
  refine ⟨(_, _), h1, h2, ?_⟩
  have := sin_sq_add_cos_sq (ψ0 + r * t)
  simp only [toBody]
  linear_combination (-vl * r) * this

/-- P06-13 06:78 'a_lat = v_0 psi_dot_0 (the rear-axle acceleration on the steady
circle)'; also covers P08-01 08:12 'a_y = v psi_dot'. -/
theorem steady_circle_a_lat (ψ0 r v vl t : ℝ) : ∃ a : ℝ × ℝ,
    HasDerivAt (fun s => (circVel ψ0 r v vl s).1) a.1 t ∧
    HasDerivAt (fun s => (circVel ψ0 r v vl s).2) a.2 t ∧
    (toBody (ψ0 + r * t) a).2 = aY v r := by
  obtain ⟨h1, h2⟩ := circVel_deriv ψ0 r v vl t
  refine ⟨(_, _), h1, h2, ?_⟩
  have := sin_sq_add_cos_sq (ψ0 + r * t)
  simp only [toBody, aY]
  linear_combination (v * r) * this

/-- The signed curvature (`InitContext.signedCurv`) of the rear-axle path on the steady
circle is `rearCurv`. -/
theorem rear_path_curvature (ψ0 r v vl t : ℝ) (h : v ^ 2 + vl ^ 2 ≠ 0) : ∃ a : ℝ × ℝ,
    HasDerivAt (fun s => (circVel ψ0 r v vl s).1) a.1 t ∧
    HasDerivAt (fun s => (circVel ψ0 r v vl s).2) a.2 t ∧
    InitContext.signedCurv (circVel ψ0 r v vl t) a = rearCurv v vl r := by
  obtain ⟨h1, h2⟩ := circVel_deriv ψ0 r v vl t
  refine ⟨(_, _), h1, h2, ?_⟩
  have hsc := sin_sq_add_cos_sq (ψ0 + r * t)
  have hn : (circVel ψ0 r v vl t).1 ^ 2 + (circVel ψ0 r v vl t).2 ^ 2 = v ^ 2 + vl ^ 2 := by
    simp only [circVel]; linear_combination (v ^ 2 + vl ^ 2) * hsc
  have hpos : 0 < v ^ 2 + vl ^ 2 := lt_of_le_of_ne (by positivity) (Ne.symm h)
  have hs : 0 < sqrt (v ^ 2 + vl ^ 2) := sqrt_pos.mpr hpos
  have hss := sq_sqrt hpos.le
  simp only [InitContext.signedCurv, rearCurv]
  rw [hn, div_eq_div_iff (by positivity) hs.ne']
  simp only [circVel]
  linear_combination (r * sqrt (v ^ 2 + vl ^ 2) * (v ^ 2 + vl ^ 2)) * hsc - (r * sqrt (v ^ 2 + vl ^ 2)) * hss

/-- P06-03, supporting: with psi_dot_0 = v_0 κ_0 the rear axle follows a path of
curvature κ_0 exactly when κ_0 = 0 or v_lat,ra = 0. -/
theorem rear_path_curvature_eq_iff (v κ vl : ℝ) (hv : 0 < v) :
    rearCurv v vl (v * κ) = κ ↔ κ = 0 ∨ vl = 0 := by
  have hpos : 0 < v ^ 2 + vl ^ 2 := by positivity
  have hs : 0 < sqrt (v ^ 2 + vl ^ 2) := sqrt_pos.mpr hpos
  simp only [rearCurv]
  rw [div_eq_iff hs.ne']
  constructor
  · intro h
    by_cases hκ : κ = 0
    · exact Or.inl hκ
    right
    have h1 : sqrt (v ^ 2 + vl ^ 2) = v := by
      apply mul_left_cancel₀ hκ; linarith
    have h2 := sq_sqrt hpos.le
    rw [h1] at h2
    nlinarith
  · rintro (h | h)
    · simp [h]
    · subst h; simp [sqrt_sq hv.le]; ring

/-! ## Bounds and witnesses -/

theorem arctan_tan_alphaR (p : Params) (v r : ℝ) (h : |alphaR p v r| < π / 2) :
    arctan (tan (alphaR p v r)) = alphaR p v r :=
  arctan_tan (by linarith [neg_abs_le (alphaR p v r)]) (lt_of_le_of_lt (le_abs_self _) h)

/-- Bounds on δ_ss when 0 ≤ α_r < π/2 and L psi_dot ≥ 0. -/
theorem deltaSS_bounds (p : Params) (v r : ℝ) (hv : 0 < v) (h0 : 0 ≤ alphaR p v r)
    (h1 : alphaR p v r < π / 2) (hr : 0 ≤ p.L * r) :
    alphaF p v r - alphaR p v r ≤ deltaSS p v r ∧ deltaSS p v r ≤ alphaF p v r + p.L * r / v := by
  have ht : 0 ≤ tan (alphaR p v r) := by
    rcases h0.lt_or_eq with h | h
    · exact (tan_pos_of_pos_of_lt_pi_div_two h h1).le
    · rw [← h, tan_zero]
  have hx : (vLatRa p v r + p.L * r) / v = -tan (alphaR p v r) + p.L * r / v := by
    simp only [vLatRa]; field_simp
  have hLr : 0 ≤ p.L * r / v := div_nonneg hr hv.le
  simp only [deltaSS]
  rw [hx]
  constructor
  · have : arctan (-tan (alphaR p v r)) ≤ arctan (-tan (alphaR p v r) + p.L * r / v) :=
      arctan_strictMono.monotone (by linarith)
    rw [arctan_neg, arctan_tan (by linarith) h1] at this
    linarith
  · have : arctan (-tan (alphaR p v r) + p.L * r / v) ≤ arctan (p.L * r / v) :=
      arctan_strictMono.monotone (by linarith)
    linarith [arctan_le_self hLr]

/-- A sedan-like spec with l_f + l_r = L: L = 3, l_f = l_r = 3/2, m = 1500,
C_αf = C_αr = 10^5, h_cg = 1/2, I_zz = 2500, δ_max = 1/2. -/
noncomputable def ssT1 : VehicleSpec.Tier1 :=
  { mass := 1500, cg_dist_front := 3 / 2, cg_dist_rear := 3 / 2, cg_height := 1 / 2,
    inertia_zz := 2500, cornering_stiffness_f := 100000, cornering_stiffness_r := 100000 }

noncomputable def ssWitness : VehicleSpec.VSpec :=
  { tier0 := { bbox_length := 5, wheelbase := 3, overhang_front := 1, overhang_rear := 1,
               max_steer_angle := 1 / 2 }
    tier1 := some ssT1 }

/-- `ssWitness` with l_r = 3/2 + 10^-7, so that l_f + l_r is only within the 03:31
tolerance of L (as in `VehicleSpec.cgWitness`). -/
noncomputable def ssT1G : VehicleSpec.Tier1 :=
  { ssT1 with cg_dist_rear := 3 / 2 + 1 / 10 ^ 7 }

noncomputable def ssWitnessG : VehicleSpec.VSpec :=
  { tier0 := ssWitness.tier0
    tier1 := some ssT1G }

theorem ssWitness_wf : ssWitness.WF := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · exact VehicleSpec.approxEq_of_eq _ _ (by simp [ssWitness, ssT1] <;> norm_num)
  · rintro t1 ⟨⟩; exact VehicleSpec.approxEq_of_eq _ _ (by simp [ssWitness, ssT1] <;> norm_num)
  · rintro t2 h; simp [ssWitness] at h
  · rintro d h; simp [ssWitness] at h

theorem ssWitnessG_wf : ssWitnessG.WF := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · exact VehicleSpec.approxEq_of_eq _ _ (by simp [ssWitnessG, ssWitness]; norm_num)
  · rintro t1 ⟨⟩
    apply VehicleSpec.approxEq_of_small
    simp only [ssWitnessG, ssT1G, ssT1, ssWitness]
    rw [show (3 / 2 + (3 / 2 + 1 / 10 ^ 7) - 3 : ℝ) = 1 / 10 ^ 7 by norm_num,
      abs_of_pos (by norm_num)]
    norm_num
  · rintro t2 h; simp [ssWitnessG] at h
  · rintro d h; simp [ssWitnessG] at h

/-- Feasibility (08:19) with μ = 1 at a state with 0 ≤ α_r ≤ 1/100, |α_f| ≤ 1/100,
0 ≤ L psi_dot / v ≤ 1/100, |a_y| ≤ 1 and δ_max = 1/2. -/
theorem feasible_of_small (p : Params) (v r : ℝ) (hv : 0 < v) (hδ : p.δmax = 1 / 2)
    (h0 : 0 ≤ alphaR p v r) (h1 : alphaR p v r ≤ 1 / 100) (hf : |alphaF p v r| ≤ 1 / 100)
    (hr : 0 ≤ p.L * r) (hr' : p.L * r / v ≤ 1 / 100) (ha : |aY v r| ≤ 1) :
    ¬ infeasible p 1 (deltaSS p v r) (aY v r) := by
  obtain ⟨b1, b2⟩ := deltaSS_bounds p v r hv h0 (by linarith [pi_gt_three]) hr
  rw [abs_le] at hf
  simp only [infeasible, gStd, not_or, not_lt, hδ]
  exact ⟨abs_le.mpr ⟨by linarith, by linarith⟩, by linarith⟩

/-! ## §8 rows -/

/-- P08-02 08:14 'δ_ss = δ_KS = arctan(L psi_dot / v) for v ≠ 0': δ_KS is the unique
angle in (−π/2, π/2) that the KS yaw rate 17:111 'psi_dot = v/L tan δ' maps to psi_dot,
stated multiplied by L. -/
theorem deltaKS_inverts (L v r : ℝ) (hv : v ≠ 0) :
    deltaKS L v r ∈ Set.Ioo (-(π / 2)) (π / 2) ∧ v * tan (deltaKS L v r) = L * r ∧
    ∀ δ ∈ Set.Ioo (-(π / 2)) (π / 2), v * tan δ = L * r → δ = deltaKS L v r := by
  refine ⟨⟨neg_pi_div_two_lt_arctan _, arctan_lt_pi_div_two _⟩, ?_, ?_⟩
  · simp only [deltaKS, tan_arctan]; field_simp
  · rintro δ ⟨h1, h2⟩ h
    have : tan δ = L * r / v := by field_simp; linarith
    simp only [deltaKS, ← this, arctan_tan h1 h2]

/-- P08-03, supporting. 08:18 'At this state the axle forces sum to m a_y and the yaw
moment l_f F_yf − l_r F_yr is zero': the moment is zero, and the forces sum to m a_y
exactly when m a_y = 0 or l_f + l_r = L. -/
theorem axle_balance (p : Params) (v r : ℝ) (hL : p.L ≠ 0) :
    p.lf * Fyf p v r - p.lr * Fyr p v r = 0 ∧
    (Fyf p v r + Fyr p v r = p.m * aY v r ↔ p.m * aY v r = 0 ∨ p.lf + p.lr = p.L) := by
  refine ⟨by simp only [Fyf, Fyr]; ring, ?_⟩
  rw [← sub_eq_zero, show Fyf p v r + Fyr p v r - p.m * aY v r =
      p.m * aY v r * ((p.lf + p.lr - p.L) / p.L) by simp only [Fyf, Fyr]; field_simp; ring]
  simp [mul_eq_zero, div_eq_zero_iff, sub_eq_zero, hL]

/-- P08-03, refuted. 08:18 'At this state the axle forces sum to m a_y and the yaw moment
l_f F_yf − l_r F_yr is zero'. A spec accepted under 03:31 has l_f + l_r only within
tolerance of L, and then at a feasible ST state (v = 10 m/s, psi_dot = 1/100 rad/s) the
§8 axle forces do not sum to m a_y. -/
theorem axle_sum_ne : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v r : ℝ, 1 ≤ v ∧
    ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v r) (aY v r) ∧
    Fyf (Params.ofSpec s.tier0 t1) v r + Fyr (Params.ofSpec s.tier0 t1) v r ≠ t1.mass * aY v r := by
  refine ⟨ssWitnessG, ssWitnessG_wf, ssT1G, rfl, 10, 1 / 100, by norm_num, ?_, ?_⟩
  · apply feasible_of_small _ _ _ (by norm_num) <;>
      simp [Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaR, alphaF, Fyf, Fyr, aY, abs_le] <;> norm_num
  · simp [Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, Fyf, Fyr, aY]; norm_num

/-- P08-04 08:17 'v_lat,ra = −v tan α_r, δ_ss = α_f + arctan((v_lat,ra + L psi_dot)/v)',
evaluated by the §17 slip formulas (17:115) at v_y = v_lat,ra + l_r psi_dot (17:104). -/
theorem st_slip_reproduced (p : Params) (v r : ℝ) (hv : 1 ≤ v) :
    dstAlphaR p v (vLatRa p v r + p.lr * r) r = arctan (tan (alphaR p v r)) ∧
    dstAlphaF p v (vLatRa p v r + p.lr * r) r (deltaSS p v r) =
      alphaF p v r + (arctan ((vLatRa p v r + p.L * r) / v) -
        arctan ((vLatRa p v r + (p.lf + p.lr) * r) / v)) := by
  have hv0 : v ≠ 0 := by linarith
  constructor
  · simp only [dstAlphaR, vLatRa]
    rw [show (-v * tan (alphaR p v r) + p.lr * r - p.lr * r) / v = -tan (alphaR p v r) by
      field_simp; ring, arctan_neg, neg_neg]
  · simp only [dstAlphaF, deltaSS]
    rw [show vLatRa p v r + p.lr * r + p.lf * r = vLatRa p v r + (p.lf + p.lr) * r by ring]
    ring

/-- P08-05 08:17 'β_cg = arctan((v_lat,ra + l_r psi_dot)/v)': the slip angle of the CG
velocity of the rigid body, whose world velocity is the rear-axle velocity
R(ψ)(v, v_lat,ra) plus psi_dot ẑ × R(ψ)(l_r, 0). -/
theorem betaCG_is_cg_slip (p : Params) (v r ψ : ℝ) (hv : 1 ≤ v) :
    toBody ψ (v * cos ψ - vLatRa p v r * sin ψ - p.lr * r * sin ψ,
        v * sin ψ + vLatRa p v r * cos ψ + p.lr * r * cos ψ) = (v, vLatRa p v r + p.lr * r) ∧
    betaCG p v r ∈ Set.Ioo (-(π / 2)) (π / 2) ∧
    ∃ s > 0, ((v : ℝ), vLatRa p v r + p.lr * r) = (s * cos (betaCG p v r), s * sin (betaCG p v r)) := by
  have hv0 : 0 < v := by linarith
  have hsc := sin_sq_add_cos_sq ψ
  refine ⟨?_, ⟨neg_pi_div_two_lt_arctan _, arctan_lt_pi_div_two _⟩, ?_⟩
  · simp only [toBody, Prod.mk.injEq]
    constructor
    · linear_combination v * hsc
    · linear_combination (vLatRa p v r + p.lr * r) * hsc
  · set x := (vLatRa p v r + p.lr * r) / v with hx
    have hb : betaCG p v r = arctan x := rfl
    have hxv : vLatRa p v r + p.lr * r = v * x := by rw [hx]; field_simp
    rw [hb, hxv]
    clear_value x
    have hq : 0 < sqrt (1 + x ^ 2) := sqrt_pos.mpr (by positivity)
    refine ⟨v * sqrt (1 + x ^ 2), by positivity, ?_⟩
    rw [cos_arctan, sin_arctan, Prod.mk.injEq]
    constructor <;> field_simp

/-- P08-07 08:19 'A steady state is infeasible if |δ_ss| > δ_max, or if |a_y| > μ g with
g = 9.80665 m/s^2' -/
theorem infeasible_iff (p : Params) (μ v r : ℝ) (t : Tier) (ph : Phase) :
    infeasible p μ (solve t p ph v r).delta (aY v r) ↔
      p.δmax < |(solve t p ph v r).delta| ∨ 9.80665 * μ < |v * r| := by
  simp only [infeasible, gStd, aY, mul_comm μ]

/-! ## §6.2 rows -/

/-- P06-03, refuted. 06:73 'It sets psi_dot_0 = v_0 kappa_0 and solves the steady state of
§8 ... so the rear-axle velocity is tangent to the lane and the actor follows it.' At a
feasible ST spawn state (v_0 = 10 m/s, κ_0 = 1/1000 1/m) v_lat,ra ≠ 0, so the rear axle
moves on a circle of curvature `rearCurv` (`rear_path_curvature`) that differs from κ_0
(`rear_path_curvature_eq_iff`): the actor does not follow the lane. -/
theorem rear_path_not_followed : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v κ : ℝ,
    1 ≤ v ∧ κ ≠ 0 ∧
    ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v (v * κ))
      (aY v (v * κ)) ∧
    rearCurv v (vLatRa (Params.ofSpec s.tier0 t1) v (v * κ)) (v * κ) ≠ κ := by
  refine ⟨ssWitness, ssWitness_wf, ssT1, rfl, 10, 1 / 1000, by norm_num, by norm_num, ?_, ?_⟩
  · apply feasible_of_small _ _ _ (by norm_num) <;>
      simp [Params.ofSpec, ssWitness, ssT1, alphaR, alphaF, Fyf, Fyr, aY, abs_le] <;> norm_num
  · rw [Ne, rear_path_curvature_eq_iff _ _ _ (by norm_num)]
    have hα : alphaR (Params.ofSpec ssWitness.tier0 ssT1) 10 (10 * (1 / 1000)) = 3 / 4000 := by
      simp [Params.ofSpec, ssWitness, ssT1, alphaR, Fyr, aY]; norm_num
    have ht : 0 < tan (3 / 4000 : ℝ) :=
      tan_pos_of_pos_of_lt_pi_div_two (by norm_num) (by linarith [pi_gt_three])
    simp only [vLatRa, hα]
    rintro (h | h)
    · norm_num at h
    · nlinarith

/-- P06-37 06:96 'For linear tires, δ_ss − δ_KS ≈ K_us v_lon psi_dot, where
K_us = m/L (l_r/C_αf − l_f/C_αr)': α_f − α_r = K_us a_y exactly, and δ_ss − δ_KS agrees
with K_us v psi_dot to first order as psi_dot → 0. -/
theorem size_of_change (p : Params) (v : ℝ) (hv : 1 ≤ v) :
    (∀ r, alphaF p v r - alphaR p v r = Kus p * aY v r) ∧
    (fun r => deltaSS p v r - deltaKS p.L v r - Kus p * v * r) =o[nhds 0] (fun r => r) := by
  have hv0 : v ≠ 0 := by linarith
  have hdiff : ∀ r, alphaF p v r - alphaR p v r = Kus p * aY v r := by
    intro r; simp only [alphaF, alphaR, Fyf, Fyr, Kus, aY]; ring
  refine ⟨hdiff, ?_⟩
  set c := p.m * v * p.lf / p.L / p.Car
  have hαR : ∀ r, alphaR p v r = c * r := by
    intro r; simp only [alphaR, Fyr, aY, c]; ring
  have hf : ∀ r, deltaSS p v r - deltaKS p.L v r - Kus p * v * r =
      c * r + arctan ((-v * tan (c * r) + p.L * r) / v) - arctan (p.L * r / v) := by
    intro r
    have := hdiff r
    simp only [deltaSS, deltaKS, vLatRa, hαR, aY] at this ⊢
    linear_combination this
  have hc : HasDerivAt (fun r => c * r) c 0 := by simpa using (hasDerivAt_id (0 : ℝ)).const_mul c
  have htan : HasDerivAt (fun r => tan (c * r)) (1 / cos (c * 0) ^ 2 * c) 0 :=
    (hasDerivAt_tan (by simp)).comp 0 hc
  have hin : HasDerivAt (fun r => (-v * tan (c * r) + p.L * r) / v)
      ((-v * (1 / cos (c * 0) ^ 2 * c) + p.L * 1) / v) 0 :=
    ((htan.const_mul (-v)).add ((hasDerivAt_id (0 : ℝ)).const_mul p.L)).div_const v
  have hks : HasDerivAt (fun r => p.L * r / v) (p.L * 1 / v) 0 :=
    ((hasDerivAt_id (0 : ℝ)).const_mul p.L).div_const v
  have hg := (hc.add hin.arctan).sub hks.arctan
  have hg0 : HasDerivAt (fun r => deltaSS p v r - deltaKS p.L v r - Kus p * v * r) 0 0 := by
    rw [funext hf]
    convert hg using 1
    simp; field_simp; ring
  have h0 : deltaSS p v 0 - deltaKS p.L v 0 - Kus p * v * 0 = 0 := by rw [hf]; simp
  have := hasDerivAt_iff_isLittleO.mp hg0
  simp only [h0, sub_zero, smul_zero] at this
  exact this

/-- The §17 rate residuals at the §8 state with δ = δ_ss and v_y = v_lat,ra + l_r psi_dot. -/
theorem dst_residuals (p : Params) (Izz v r : ℝ) (hv : 1 ≤ v) (hCf : p.Caf ≠ 0)
    (hCr : p.Car ≠ 0) (hα : |alphaR p v r| < π / 2) :
    dstVyDot p v (vLatRa p v r + p.lr * r) r (deltaSS p v r) =
      (Fyf p v r + Fyr p v r) / p.m + p.Caf * (arctan ((vLatRa p v r + p.L * r) / v) -
        arctan ((vLatRa p v r + (p.lf + p.lr) * r) / v)) / p.m - v * r ∧
    dstRDot p Izz v (vLatRa p v r + p.lr * r) r (deltaSS p v r) =
      p.lf * p.Caf * (arctan ((vLatRa p v r + p.L * r) / v) -
        arctan ((vLatRa p v r + (p.lf + p.lr) * r) / v)) / Izz := by
  obtain ⟨hR, hF⟩ := st_slip_reproduced p v r hv
  rw [arctan_tan_alphaR p v r hα] at hR
  have e1 : p.Caf * alphaF p v r = Fyf p v r := by simp only [alphaF]; field_simp
  have e2 : p.Car * alphaR p v r = Fyr p v r := by simp only [alphaR]; field_simp
  have e3 : p.lf * Fyf p v r - p.lr * Fyr p v r = 0 := by simp only [Fyf, Fyr]; ring
  simp only [dstVyDot, dstRDot, hR, hF]
  constructor
  · rw [← e1, ← e2]; ring
  · congr 1; linear_combination p.lf * e1 - p.lr * e2 + e3

/-- P06-23, supporting: with l_f + l_r = L ≠ 0, nonzero m, C_αf, C_αr and |α_r| < π/2,
none of which the spec states, the incoming `DynamicSingleTrack` is at rest at δ_ss. -/
theorem dst_balanced_of_exact (p : Params) (Izz v r : ℝ) (hv : 1 ≤ v) (hm : p.m ≠ 0)
    (hCf : p.Caf ≠ 0) (hCr : p.Car ≠ 0) (hL : p.L ≠ 0) (G1 : p.lf + p.lr = p.L)
    (G2 : |alphaR p v r| < π / 2) :
    dstVyDot p v (vLatRa p v r + p.lr * r) r (deltaSS p v r) = 0 ∧
    dstRDot p Izz v (vLatRa p v r + p.lr * r) r (deltaSS p v r) = 0 := by
  obtain ⟨h1, h2⟩ := dst_residuals p Izz v r hv hCf hCr G2
  rw [G1, sub_self, mul_zero, zero_div, add_zero] at h1
  rw [G1, sub_self, mul_zero, zero_div] at h2
  refine ⟨?_, h2⟩
  rw [h1, (axle_balance p v r hL).2.mpr (Or.inr G1), aY, mul_div_cancel_left₀ _ hm, sub_self]

/-- The front slip angle of `dstAlphaF` moves one for one with the steering angle. -/
theorem dstVyDot_add (p : Params) (vx vy r δ e : ℝ) :
    dstVyDot p vx vy r (δ + e) = dstVyDot p vx vy r δ + p.Caf * e / p.m := by
  simp only [dstVyDot, dstAlphaF]; ring

/-- P06-23, first counterexample. 06:84 'balanced at the first step if the upstream
steering command reproduces δ_ss, that is, if the re-trim reports no
DL_STATUS_WARN_TRIM_MISMATCH', where the check reports only 'if the steering angles differ
by more than 10^-3 rad' (06:87). With l_f + l_r = L exactly and C_αf ≠ 0, a command
δ = δ_ss + 10^-3 passes the check, and at a feasible ST state (v = 10 m/s,
psi_dot = 1/100 rad/s) the §17 `DynamicSingleTrack` front lateral force is unbalanced:
v̇_y ≠ 0. -/
theorem dst_not_balanced_within_trim : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1,
    ∃ v r δ : ℝ, 1 ≤ v ∧
    t1.cg_dist_front + t1.cg_dist_rear = s.tier0.wheelbase ∧ t1.cornering_stiffness_f ≠ 0 ∧
    ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v r) (aY v r) ∧
    |δ - deltaSS (Params.ofSpec s.tier0 t1) v r| ≤ 1 / 1000 ∧
    dstVyDot (Params.ofSpec s.tier0 t1) v
      (vLatRa (Params.ofSpec s.tier0 t1) v r + (Params.ofSpec s.tier0 t1).lr * r) r δ ≠ 0 := by
  set p := Params.ofSpec ssWitness.tier0 ssT1
  refine ⟨ssWitness, ssWitness_wf, ssT1, rfl, 10, 1 / 100, deltaSS p 10 (1 / 100) + 1 / 1000,
    by norm_num, by simp [ssWitness, ssT1], by simp [ssT1], ?_, ?_, ?_⟩
  · apply feasible_of_small _ _ _ (by norm_num) <;>
      simp [Params.ofSpec, ssWitness, ssT1, alphaR, alphaF, Fyf, Fyr, aY, abs_le] <;> norm_num
  · rw [add_sub_cancel_left, abs_of_pos (by norm_num)]
  · have hα : alphaR p 10 (1 / 100) = 3 / 4000 := by
      simp [p, Params.ofSpec, ssWitness, ssT1, alphaR, Fyr, aY]; norm_num
    obtain ⟨h0, -⟩ := dst_balanced_of_exact p 2500 10 (1 / 100) (by norm_num)
      (by simp [p, Params.ofSpec, ssT1]) (by simp [p, Params.ofSpec, ssT1])
      (by simp [p, Params.ofSpec, ssT1]) (by simp [p, Params.ofSpec, ssWitness])
      (by simp [p, Params.ofSpec, ssWitness, ssT1])
      (by rw [hα, abs_of_pos (by norm_num)]; linarith [pi_gt_three])
    rw [dstVyDot_add, h0]
    simp [Params.ofSpec, ssT1]

/-- P06-23, second counterexample. A spec accepted under 03:31 has l_f + l_r only within tolerance of L; at a feasible
ST state of such a spec (v = 10 m/s, psi_dot = 1/100 rad/s) the §17 `DynamicSingleTrack`
(17:115-116) with linear tires, started at the §8 state with δ = δ_ss, has ṙ ≠ 0. -/
theorem dst_not_balanced_tolerance : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v r : ℝ, 1 ≤ v ∧
    ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v r) (aY v r) ∧
    dstRDot (Params.ofSpec s.tier0 t1) t1.inertia_zz v
      (vLatRa (Params.ofSpec s.tier0 t1) v r + (Params.ofSpec s.tier0 t1).lr * r) r
      (deltaSS (Params.ofSpec s.tier0 t1) v r) ≠ 0 := by
  refine ⟨ssWitnessG, ssWitnessG_wf, ssT1G, rfl, 10, 1 / 100, by norm_num, ?_, ?_⟩
  · apply feasible_of_small _ _ _ (by norm_num) <;>
      simp [Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaR, alphaF, Fyf, Fyr, aY, abs_le] <;> norm_num
  · set p := Params.ofSpec ssWitnessG.tier0 ssT1G
    have hα : alphaR p 10 (1 / 100) = 3 / 4000 := by
      simp [p, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness, alphaR, Fyr, aY]; norm_num
    obtain ⟨-, h⟩ := dst_residuals p 2500 10 (1 / 100) (by norm_num)
      (by simp [p, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness]) (by simp [p, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness])
      (by rw [hα, abs_of_pos (by norm_num)]; linarith [pi_gt_three])
    have hI : ssT1G.inertia_zz = 2500 := rfl
    rw [hI, h]
    have hne : arctan ((vLatRa p 10 (1 / 100) + p.L * (1 / 100)) / 10) ≠
        arctan ((vLatRa p 10 (1 / 100) + (p.lf + p.lr) * (1 / 100)) / 10) := by
      intro e
      have := arctan_injective e
      simp [p, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness] at this
      norm_num at this
    have hk : p.lf * p.Caf ≠ 0 := by simp [p, Params.ofSpec, ssWitnessG, ssT1G, ssT1, ssWitness]
    exact div_ne_zero (mul_ne_zero hk (sub_ne_zero.mpr hne)) (by norm_num)

/-- P06-23, refuted. 06:84 'With linear tires, the lateral force and yaw moment of the
incoming model are balanced at the first step if the upstream steering command reproduces
δ_ss, that is, if the re-trim reports no DL_STATUS_WARN_TRIM_MISMATCH'. Both counterexamples:
a command within the 10^-3 rad trim threshold with l_f + l_r = L exactly
(`dst_not_balanced_within_trim`), and δ_ss itself with l_f + l_r within the 03:31
tolerance of L (`dst_not_balanced_tolerance`). The conditional result is
`dst_balanced_of_exact`. -/
theorem dst_not_balanced :
    (∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v r δ : ℝ, 1 ≤ v ∧
      t1.cg_dist_front + t1.cg_dist_rear = s.tier0.wheelbase ∧ t1.cornering_stiffness_f ≠ 0 ∧
      ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v r) (aY v r) ∧
      |δ - deltaSS (Params.ofSpec s.tier0 t1) v r| ≤ 1 / 1000 ∧
      dstVyDot (Params.ofSpec s.tier0 t1) v
        (vLatRa (Params.ofSpec s.tier0 t1) v r + (Params.ofSpec s.tier0 t1).lr * r) r δ ≠ 0) ∧
    (∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ v r : ℝ, 1 ≤ v ∧
      ¬ infeasible (Params.ofSpec s.tier0 t1) 1 (deltaSS (Params.ofSpec s.tier0 t1) v r) (aY v r) ∧
      dstRDot (Params.ofSpec s.tier0 t1) t1.inertia_zz v
        (vLatRa (Params.ofSpec s.tier0 t1) v r + (Params.ofSpec s.tier0 t1).lr * r) r
        (deltaSS (Params.ofSpec s.tier0 t1) v r) ≠ 0) :=
  ⟨dst_not_balanced_within_trim, dst_not_balanced_tolerance⟩

end Driveline.SteadyState
