#ifndef DRIVELINE_ABI_H
#define DRIVELINE_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

#define DL_ABI_VERSION_0_5 0x00000500U

typedef enum {
    DL_STATUS_OK                    = 0,
    DL_STATUS_WARN_UNDERFLOW        = 1,
    DL_STATUS_WARN_FMU_COLD_SPLICE  = 2,
    DL_STATUS_WARN_TRIM_MISMATCH    = 3,
    DL_STATUS_ERR_INVALID_ARG       = -1,
    DL_STATUS_ERR_TIER_MISSING      = -2,
    DL_STATUS_ERR_NUMERIC           = -3,
    DL_STATUS_ERR_UNSUPPORTED_MODE  = -4,
    DL_STATUS_ERR_STATE             = -5
} dl_status_t;

typedef void* dl_component_handle_t;

/* ==========================================================================
 * 1. STRATIFIED VEHICLE PARAMETER TIERS (Pointer-Free Inline Layout)
 * ========================================================================== */

typedef struct {
    double bbox_length, bbox_width, bbox_height; /* L_bbox, W_bbox, H_bbox [m] */
    double wheelbase;                            /* L = l_f + l_r [m] */
    double overhang_front, overhang_rear;        /* o_f, o_r [m] */
    double max_steer_angle;                      /* delta_max [rad] */
    double max_steer_rate;                       /* delta_dot_max [rad/s] */
    double steering_ratio;                       /* i_s [-] */
} dl_kinematic_params_t;

typedef struct {
    double mass;                                 /* m [kg] */
    double cg_dist_front, cg_dist_rear;          /* l_f, l_r [m] */
    double cg_height;                            /* h_cg [m] */
    double inertia_zz;                           /* I_zz [kg*m^2] */
    double cornering_stiffness_f;                /* C_alpha_f [N/rad] */
    double cornering_stiffness_r;                /* C_alpha_r [N/rad] */
    double aero_cd, aero_area;                   /* [-], [m^2] */
    double rolling_resistance_coeff;             /* C_rr [-] */
} dl_single_track_params_t;

typedef struct {
    double sprung_mass;                          /* m_s [kg] */
    double unsprung_mass_f, unsprung_mass_r;     /* Per-axle m_uf, m_ur [kg] */
    double inertia_xx, inertia_yy, inertia_xz;   /* [kg*m^2] (I_zz in Tier 1) */
    double track_width_f, track_width_r;         /* t_f, t_r [m] */
    double susp_stiffness_f, susp_stiffness_r;   /* Per-wheel K_sf, K_sr [N/m] */
    double susp_damping_f, susp_damping_r;       /* Per-wheel C_sf, C_sr [N*s/m] */
    double arb_stiffness_f, arb_stiffness_r;     /* [N*m/rad] */
    double tire_effective_radius;                /* R_eff [m] */
    double wheel_polar_inertia;                  /* I_w [kg*m^2] */
    double max_drive_torque;                     /* Engine/motor shaft peak [N*m] */
    double max_brake_torque;                     /* Sum over wheels, at wheels [N*m] */
    double final_drive_ratio;                    /* i_fd [-] */
    double gear_ratios[10];                      /* Forward gears 1..10 [-] */
    uint32_t num_gears, _pad;
} dl_multibody_params_t;

typedef struct {
    uint8_t  deck_type;        /* 0:NONE, 1:PACEJKA_TIR, 2:SOLVER_URI */
    uint8_t  precedence_mode;  /* 0:SUPPLEMENT_ONLY, 1:OVERRIDE_TIER1_2 */
    uint16_t _pad;
    uint32_t _pad2;
    char     uri[256];         /* Null-terminated path or URI */
} dl_custom_deck_t;

typedef struct {
    uint32_t populated_tiers_mask; /* Bit 0: Tier0, Bit 1: Tier1, Bit 2: Tier2, Bit 3: Tier3 */
    uint32_t _pad;
    dl_kinematic_params_t    tier0;
    dl_single_track_params_t tier1;
    dl_multibody_params_t    tier2;
    dl_custom_deck_t         tier3;
} dl_vehicle_spec_t;

/* ==========================================================================
 * 2. MAP REFERENCES, PRIORS, & PERCEPTION SLICE CONTRACTS
 * ========================================================================== */

typedef struct {
    char     road_id[64];
    int32_t  lane_id;
    uint32_t _pad;
} dl_lane_ref_t;

typedef struct {
    uint32_t      count;                         /* Valid entries in nodes[] */
    uint32_t      _pad;
    dl_lane_ref_t nodes[64];
} dl_route_t;

typedef struct {
    uint64_t target_actor_id;
    double   rel_x, rel_y, rel_z;                /* Sensor frame [m] */
    double   rel_vx, rel_vy;                     /* Sensor frame [m/s] */
    double   rel_yaw;                            /* [rad] */
    double   range, bearing, ttc_lon;            /* [m, rad, s] */
    char     road_id[64];
    int32_t  lane_id;
    uint32_t object_class;                       /* 0:UNKNOWN, 1:CAR, 2:TRUCK, 3:VRU */
    double   confidence;                         /* [0.0, 1.0] */
} dl_target_track_t;

typedef struct {
    char     ego_road_id[64];
    int32_t  ego_lane_id;
    uint8_t  left_lane_free, right_lane_free;
    uint16_t _pad;
    double   ego_s, ego_d, lead_ttc;             /* [m, m, s] */
    uint32_t num_tracks, _pad2;
    dl_target_track_t tracks[32];
} dl_visual_slice_t;

typedef struct {
    uint8_t  has_primary_target;
    uint8_t  _pad[3];
    uint32_t num_tracks;
    double   primary_range, primary_azimuth, primary_rcs; /* [m, rad, dBsm] */
    dl_target_track_t tracks[32];
} dl_radar_slice_t;

typedef struct {
    double   obstacle_confidence, lane_line_confidence;   /* [0.0, 1.0] */
    double   d_lane_center_est, heading_error_est;        /* [m, rad] */
    uint32_t num_tracks, _pad;
    dl_target_track_t tracks[32];
} dl_camera_slice_t;

typedef struct {
    double   mu_fl, mu_fr, mu_rl, mu_rr;         /* Per-corner friction [-] */
    double   mu_mean;                            /* Mean friction under actor [-] */
    double   road_grade, road_bank, elevation_z; /* [rad, rad, m] */
} dl_surface_slice_t;

typedef struct {
    dl_visual_slice_t  visual;
    dl_radar_slice_t   radar;
    dl_camera_slice_t  camera;
    dl_surface_slice_t surface;
} dl_sensor_bundle_t;

/* Serialized SliceBuffer prefix. Followed by count entries, newest first.
 * Each entry is uint64_t t_ns followed by the slice struct. */
typedef struct {
    uint32_t capacity;                           /* N */
    uint32_t count;                              /* Valid entries, <= N */
    uint32_t entry_size;                         /* 8 + sizeof(slice struct) */
    uint32_t _pad;
} dl_slice_buffer_header_t;

/* In-process ring view. Entry k (k = 0 newest) starts at
 * entries + ((head + capacity - k) % capacity) * entry_size. */
typedef struct {
    dl_slice_buffer_header_t hdr;
    uint32_t       head;                         /* Slot of the newest entry */
    uint32_t       _pad;
    const uint8_t* entries;
} dl_slice_buffer_view_t;

/* ==========================================================================
 * 3. CANONICAL CHECKPOINT STRUCTS (Stages 1, 2, & 3)
 * ========================================================================== */

typedef struct {
    double x, y, psi_ref, kappa_ref;             /* [m, m, rad, 1/m] */
} dl_waypoint_t;

typedef struct {
    double t, x, y, psi, v, a, kappa, _pad;      /* [s, m, m, rad, m/s, m/s^2, 1/m] */
} dl_traj_point_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* Bitmask of active intent fields */
    uint8_t  lon_mode;                           /* 0:ACCEL, 1:VEL, 2:GAP */
    uint8_t  lat_mode;                           /* 0:LANE, 1:PATH, 2:TRAJ */
    uint8_t  turn_signal;                        /* 0:NONE, 1:L, 2:R, 3:HAZ */
    uint8_t  _pad;
    double   a_ref, v_ref, s_stop;               /* [m/s^2, m/s, m] */
    uint64_t gap_target_actor_id;
    double   time_gap_ref, distance_gap_min;     /* [s, m] */
    char     target_road_id[64];
    int32_t  target_lane_id;
    uint32_t num_waypoints;
    double   d_ref;                              /* [m] */
    uint32_t num_traj_points, _pad2;
    dl_waypoint_t   path_points[64];
    dl_traj_point_t trajectory[64];
} dl_intent_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* 0x1:a_lon, 0x2:jerk, 0x4:angle, 0x8:rate */
    uint32_t _pad;
    double   a_lon_cmd, jerk_lon_cmd;            /* [m/s^2, m/s^3] */
    double   steer_angle_cmd, steer_rate_cmd;    /* [rad, rad/s] */
} dl_kinematic_control_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    uint32_t valid_mask;                         /* 0x1:thr, 0x2:brk, 0x4:steer, 0x8:trq, 0x10:gear */
    uint8_t  gear_mode;                          /* 0:PARK, 1:REVERSE, 2:NEUTRAL, 3:DRIVE */
    int8_t   manual_gear_index;                  /* 0:Auto, 1..10:Manual gear */
    uint16_t _pad;
    double   throttle, brake;                    /* [0.0, 1.0] */
    double   steering_wheel_norm;                /* [-1.0, 1.0] */
    double   steering_torque_nm;                 /* [N*m] */
} dl_actuator_control_frame_t;

typedef struct {
    uint64_t actor_id;
    uint64_t timestamp_ns;                       /* [ns] */
    double   pos_x, pos_y, pos_z;                /* Rear-axle World [m] */
    double   roll, pitch, yaw;                   /* Intrinsic Z-Y'-X'' Euler [rad] */
    double   v_lon, v_lat, yaw_rate;             /* Rear-axle Body Twist [m/s, rad/s] */
    double   a_lon, a_lat;                       /* Rear-axle Body Accel [m/s^2] */
    double   front_wheel_angle;                  /* Road-wheel delta [rad] */
    double   slip_angle_beta_cg;                 /* Sideslip angle at CG beta_cg [rad] */
    char     road_id[64];
    int32_t  lane_id;
    uint32_t _pad;
    double   frenet_s, frenet_d;                 /* Cached Frenet [m] */
} dl_kinematic_state_t;

/* ==========================================================================
 * 4. POINTER-FREE INITIALIZATION, WARM-START, & BATCH CONTEXTS
 * ========================================================================== */

typedef struct {
    double omega;                                /* Wheel spin [rad/s] */
    double steer_angle;                          /* Corner road-wheel steer [rad] */
    double slip_ratio_kappa, slip_angle_alpha;   /* [-], [rad] */
    double susp_deflection_z, susp_velocity_dz;  /* [m], [m/s] */
    double normal_load_fz, surface_mu;           /* [N], [-] */
} dl_wheel_corner_state_t;

typedef struct {
    double   motor_or_engine_speed_rads;         /* [rad/s] (Strict SI) */
    double   actual_drive_torque_nm;             /* [N*m] */
    double   brake_pressure_pa[8];               /* [Pa] (Strict SI) */
    uint8_t  gear_mode;                          /* 0:P, 1:R, 2:N, 3:D */
    int8_t   active_gear_index;                  /* -1:R, 0:N, 1..10:Forward */
    uint8_t  _pad[6];
} dl_powertrain_state_t;

typedef struct {
    uint32_t abi_version;                        /* Must equal DL_ABI_VERSION_0_5 */
    uint32_t struct_size;                        /* sizeof(dl_init_context_t) */
    uint64_t sim_time_ns;                        /* [ns] */
    uint8_t  is_warm_start;                      /* 0:ColdInit, 1:WarmStart */
    uint8_t  trim_equilibrium;                   /* 1:Solve quasi-static trim */
    uint16_t _pad;
    uint32_t num_wheels;                         /* 0 (no Tier 2) or 4 */

    dl_kinematic_state_t          chassis_state;
    dl_wheel_corner_state_t       wheels[8];
    dl_powertrain_state_t         powertrain;

    dl_intent_frame_t             latched_intent;
    dl_kinematic_control_frame_t  latched_kinematic_ctrl;
    dl_actuator_control_frame_t   latched_actuator_ctrl;

    dl_vehicle_spec_t             vehicle_spec;  /* Inline pointer-free spec */
} dl_init_context_t;

/* One input port, one entry per actor. kind 0: frame or prior struct.
 * kind 1: dl_slice_buffer_view_t. */
typedef struct {
    const void*    data;                         /* Array [actor_count] */
    uint32_t       stride;                       /* Bytes between actor entries */
    uint32_t       kind;
} dl_port_io_t;

/* Step I/O for every cardinality. A 1:1 component has actor_count = 1. */
typedef struct {
    uint64_t            sim_time_ns;
    uint64_t            dt_step_ns;
    uint32_t            actor_count;             /* Active actors M */
    uint32_t            num_inputs;              /* Declared input port count */
    const uint64_t*     actor_ids;               /* Array [actor_count], ascending */
    const dl_port_io_t* inputs;                  /* Array [num_inputs], declared order */
    void*               outputs;                 /* Array [actor_count] of output frames */
    uint32_t            output_stride;
    uint32_t            _pad;
} dl_batch_step_io_t;

/* Membership Mutation Descriptor (Supports both Join and Leave at t > 0) */
typedef struct {
    uint64_t                sim_time_ns;
    uint32_t                active_actor_count;
    uint32_t                added_actor_count;
    const uint64_t*         active_actor_ids;    /* Array [active_actor_count] */
    const dl_init_context_t* added_init_contexts;/* Array [added_actor_count] for warm join */
} dl_membership_change_t;

/* ==========================================================================
 * 5. HOST MAP CALLBACKS & COMPONENT FUNCTION PROTOTYPES
 * ========================================================================== */

/* host_ctx is passed back unchanged as the first argument of every callback. */
typedef struct {
    void* host_ctx;

    dl_status_t (*world_to_frenet)(void* host_ctx,
        double X, double Y, double psi, const char* hint_road_id,
        char out_road_id[64], int32_t* out_lane_id, double* out_s, double* out_d, double* out_psi_lane);

    dl_status_t (*frenet_to_world)(void* host_ctx,
        const char* road_id, int32_t lane_id, double s, double d,
        double* out_X, double* out_Y, double* out_Z, double* out_psi_lane, double* out_kappa_lane);

    dl_status_t (*sample_lane_path)(void* host_ctx,
        const char* road_id, int32_t lane_id, double s_start, double d_offset,
        double ds, uint32_t count, dl_waypoint_t* out_waypoints);

    /* Writes up to max_successors successors; *out_num_successors is the total. */
    dl_status_t (*query_lane_topology)(void* host_ctx,
        const char* road_id, int32_t lane_id,
        int32_t* out_left_lane_id, int32_t* out_right_lane_id,
        uint32_t max_successors, dl_lane_ref_t* out_successors,
        uint32_t* out_num_successors);
} dl_host_map_callbacks_t;

typedef struct {
    uint32_t        max_actors;                  /* M (1 for 1:1, N for 1:N / N:N) */
    uint32_t        num_input_ports;
    const uint32_t* port_history_depths;         /* Array [num_input_ports]; 0 = not a buffer */
} dl_structural_config_t;

typedef struct {
    char     name[56];                           /* Null-terminated DSL parameter name */
    uint32_t type;                               /* 0: f64 (SI), 1: i64 */
    uint32_t _pad;
    double   f64;
    int64_t  i64;
} dl_param_t;

/* Normative C-ABI Lifecycle Entry Points */
dl_status_t dl_instantiate(uint32_t abi_version, const char* instance_name, const dl_host_map_callbacks_t* callbacks, dl_component_handle_t* out_inst);
dl_status_t dl_set_parameters(dl_component_handle_t inst, const dl_param_t* params, uint32_t count);
dl_status_t dl_configure_structure(dl_component_handle_t inst, const dl_structural_config_t* cfg);
dl_status_t dl_enter_cold_init(dl_component_handle_t inst, uint32_t actor_count, const dl_init_context_t* init_contexts);
dl_status_t dl_enter_warm_start(dl_component_handle_t inst, uint32_t actor_count, const dl_init_context_t* init_contexts);
dl_status_t dl_exit_init_mode(dl_component_handle_t inst);
dl_status_t dl_do_step(dl_component_handle_t inst, const dl_batch_step_io_t* io);
dl_status_t dl_on_membership_change(dl_component_handle_t inst, const dl_membership_change_t* change);
dl_status_t dl_terminate(dl_component_handle_t inst);
void        dl_free_instance(dl_component_handle_t inst);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif /* DRIVELINE_ABI_H */
