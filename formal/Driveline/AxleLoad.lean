import Driveline.SteadyState
import Driveline.Angles

/-!
# Static axle and wheel normal loads (§6.2 Pass 1 steps 3 and 4)

The axle loads of 06:75, the lane-relative grade and bank of 06:74, and the per-wheel
`normal_load_fz` of 06:77.
-/

open Real

namespace Driveline.AxleLoad

open SteadyState

/-- 06:75 'F_z,f = m g cosθ_road cosφ_road l_r/L − m g sinθ_road h_cg/L' -/
noncomputable def Fzf (p : Params) (θ φ : ℝ) : ℝ :=
  p.m * gStd * cos θ * cos φ * p.lr / p.L - p.m * gStd * sin θ * p.hcg / p.L

/-- 06:75 'F_z,r = m g cosθ_road cosφ_road l_f/L + m g sinθ_road h_cg/L' -/
noncomputable def Fzr (p : Params) (θ φ : ℝ) : ℝ :=
  p.m * gStd * cos θ * cos φ * p.lf / p.L + p.m * gStd * sin θ * p.hcg / p.L

/-- 06:74 'the actor's yaw differs from its lane's driving direction by more than π/2',
with the difference of headings wrapped to (−π, π] (02:17). -/
def facesAgainst (ψ ψlane : ℝ) : Prop := π / 2 < |Angles.wrap (ψ - ψlane)|

/-- 06:74 'θ_road and φ_road are taken relative to the actor's heading: both are negated
when the actor's yaw differs from its lane's driving direction by more than π/2' -/
noncomputable def relGrade (ψ ψlane θ φ : ℝ) : ℝ × ℝ := by
  classical exact if facesAgainst ψ ψlane then (-θ, -φ) else (θ, φ)

/-- 06:77 '`wheels[0..3]` in the header's order: `normal_load_fz` is half of the axle
load', with the header order 0:FL, 1:FR, 2:RL, 3:RR (abi/driveline_abi.h:273). -/
noncomputable def wheelFz (p : Params) (θ φ : ℝ) (i : Fin 4) : ℝ :=
  if i.val < 2 then Fzf p θ φ / 2 else Fzr p θ φ / 2

theorem wrap_add_mul (y : ℝ) (n : ℤ) : Angles.wrap (y + n * (2 * π)) = Angles.wrap y := by
  unfold Angles.wrap
  rw [← zsmul_eq_mul]
  exact toIocMod_add_zsmul _ _ _ _

theorem abs_wrap_neg (x : ℝ) : |Angles.wrap (-x)| = |Angles.wrap x| := by
  obtain ⟨n, hn⟩ := Angles.wrap_eq_add x
  obtain ⟨h1, h2⟩ := Angles.wrap_mem x
  have : -x = -Angles.wrap x + n * (2 * π) := by rw [hn]; ring
  rw [this, wrap_add_mul]
  rcases h2.lt_or_eq with h | h
  · rw [Angles.wrap_of_mem ⟨by linarith, by linarith⟩, abs_neg]
  · rw [h, Angles.wrap_neg_pi]

/-- P06-06 06:75 'F_z,f = m g cosθ_road cosφ_road l_r/L − m g sinθ_road h_cg/L,
F_z,r = m g cosθ_road cosφ_road l_f/L + m g sinθ_road h_cg/L': the axle loads sum to
m g cosθ cosφ exactly when m cosθ cosφ = 0 or l_f + l_r = L. -/
theorem fz_sum_iff (p : Params) (θ φ : ℝ) (hL : p.L ≠ 0) :
    Fzf p θ φ + Fzr p θ φ = p.m * gStd * cos θ * cos φ ↔
      p.m * cos θ * cos φ = 0 ∨ p.lf + p.lr = p.L := by
  rw [← sub_eq_zero, show Fzf p θ φ + Fzr p θ φ - p.m * gStd * cos θ * cos φ =
      p.m * cos θ * cos φ * gStd * ((p.lf + p.lr - p.L) / p.L) by
    simp only [Fzf, Fzr]; field_simp; ring]
  have hg : gStd ≠ 0 := by norm_num [gStd]
  simp [mul_eq_zero, div_eq_zero_iff, sub_eq_zero, hL, hg, or_assoc]

/-- P06-07, conditional: with m > 0, L > 0 and h_cg > 0, of which the spec states no
h_cg range (03:20-21), an uphill road moves load to the rear axle. θ_road < π/2 holds since
02:27 'θ_road = σ arctan(dz/ds)'. -/
theorem uphill_moves_load_rear (p : Params) (θ φ : ℝ) (hm : 0 < p.m) (hh : 0 < p.hcg)
    (hL : 0 < p.L) (hθ : 0 < θ) (hθ' : θ < π / 2) :
    p.m * gStd * cos θ * cos φ * p.lf / p.L < Fzr p θ φ ∧
      Fzf p θ φ < p.m * gStd * cos θ * cos φ * p.lr / p.L := by
  have hs : 0 < sin θ := sin_pos_of_pos_of_lt_pi hθ (by linarith [pi_pos])
  have ht : 0 < p.m * gStd * sin θ * p.hcg / p.L := by unfold gStd; positivity
  simp only [Fzf, Fzr]
  constructor <;> linarith

/-- `ssWitness` with h_cg = 0, which no Tier 1 rule excludes. -/
noncomputable def flatWitness : VehicleSpec.VSpec :=
  { tier0 := ssWitness.tier0
    tier1 := some { ssT1 with cg_height := 0 } }

theorem flatWitness_wf : flatWitness.WF := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · exact VehicleSpec.approxEq_of_eq _ _ (by simp [flatWitness, ssWitness]; norm_num)
  · rintro t1 ⟨⟩
    exact VehicleSpec.approxEq_of_eq _ _ (by simp [flatWitness, ssWitness, ssT1])
  · rintro t2 h; simp [flatWitness] at h
  · rintro d h; simp [flatWitness] at h

/-- P06-07, refuted. 06:76 'With the §2 sign convention, an uphill road (θ_road > 0) moves
load to the rear axle.' The spec states no range for h_cg, and a spec accepted under 03:31
with h_cg = 0 on an uphill road (θ_road = 1/10, inside the 02:27 range (−π/2, π/2)) has
F_z,r and F_z,f equal to their level-road shares: no load moves. The conditional result is
`uphill_moves_load_rear`. -/
theorem uphill_no_transfer : ∃ s : VehicleSpec.VSpec, s.WF ∧ ∃ t1 ∈ s.tier1, ∃ θ φ : ℝ,
    0 < θ ∧ θ < π / 2 ∧ 0 < t1.mass ∧
    Fzr (Params.ofSpec s.tier0 t1) θ φ =
      t1.mass * gStd * cos θ * cos φ * t1.cg_dist_front / s.tier0.wheelbase ∧
    Fzf (Params.ofSpec s.tier0 t1) θ φ =
      t1.mass * gStd * cos θ * cos φ * t1.cg_dist_rear / s.tier0.wheelbase := by
  refine ⟨flatWitness, flatWitness_wf, _, rfl, 1 / 10, 0, by norm_num,
    by linarith [pi_gt_three], by simp [ssT1], ?_, ?_⟩ <;>
    simp [Fzf, Fzr, Params.ofSpec, flatWitness]

/-- P06-08 06:74 'θ_road and φ_road are taken relative to the actor's heading: both are
negated when the actor's yaw differs from its lane's driving direction by more than π/2':
the wrapped difference has magnitude in [0, π], the test is symmetric in the two
headings, and facing against the lane swaps the sign of the transfer term. -/
theorem against_lane_swaps_transfer (p : Params) (ψ ψlane θ φ : ℝ) :
    |Angles.wrap (ψ - ψlane)| ∈ Set.Icc 0 π ∧
    (facesAgainst ψ ψlane ↔ facesAgainst ψlane ψ) ∧
    (facesAgainst ψ ψlane →
      Fzf p (relGrade ψ ψlane θ φ).1 (relGrade ψ ψlane θ φ).2 =
        p.m * gStd * cos θ * cos φ * p.lr / p.L + p.m * gStd * sin θ * p.hcg / p.L ∧
      Fzr p (relGrade ψ ψlane θ φ).1 (relGrade ψ ψlane θ φ).2 =
        p.m * gStd * cos θ * cos φ * p.lf / p.L - p.m * gStd * sin θ * p.hcg / p.L) := by
  obtain ⟨h1, h2⟩ := Angles.wrap_mem (ψ - ψlane)
  refine ⟨⟨abs_nonneg _, abs_le.mpr ⟨by linarith, h2⟩⟩, ?_, ?_⟩
  · simp only [facesAgainst]
    rw [show ψlane - ψ = -(ψ - ψlane) by ring, abs_wrap_neg]
  · intro h
    simp only [relGrade, h, ite_true, Fzf, Fzr, cos_neg, sin_neg]
    constructor <;> ring

/-- P06-09 06:77 '`normal_load_fz` is half of the axle load': the two front wheels carry
F_z,f, the two rear wheels F_z,r, and the four wheels F_z,f + F_z,r. -/
theorem wheel_loads_sum (p : Params) (θ φ : ℝ) :
    wheelFz p θ φ 0 + wheelFz p θ φ 1 = Fzf p θ φ ∧
      wheelFz p θ φ 2 + wheelFz p θ φ 3 = Fzr p θ φ ∧
      ∑ i, wheelFz p θ φ i = Fzf p θ φ + Fzr p θ φ := by
  simp [wheelFz, Fin.sum_univ_four]
  ring

end Driveline.AxleLoad
