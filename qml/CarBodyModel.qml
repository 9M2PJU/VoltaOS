import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    PrincipledMaterial {
        id: housing_material
        objectName: "HOUSING"
        baseColor: "#ffe4e6e8"
        metalness: 0.20000000298023224
        roughness: 0.44999998807907104
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: hlchrome_material
        objectName: "HLCHROME"
        baseColor: "#fff8f9fc"
        metalness: 0.44999998807907104
        roughness: 0.30000001192092896
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: hlglass_material
        objectName: "HLGLASS"
        baseColor: "#8cd4d8dc"
        roughness: 0.15000000596046448
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }
    PrincipledMaterial {
        id: bulb_material
        objectName: "BULB"
        baseColor: "#ffced7e3"
        roughness: 0.05290000140666962
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: refl_material
        objectName: "REFL"
        baseColor: "#fff6f6f8"
        metalness: 0.9136999845504761
        roughness: 0.11410000175237656
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: tailred_material
        objectName: "TAILRED"
        baseColor: "#33e01930"
        metalness: 0.10000000149011612
        roughness: 0.15000000596046448
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }
    PrincipledMaterial {
        id: tailglass_material
        objectName: "TAILGLASS"
        baseColor: "#85ce1227"
        roughness: 0.05000000074505806
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }
    PrincipledMaterial {
        id: tailribu_material
        objectName: "TAILRIBU"
        baseColor: "#ff9d1423"
        metalness: 0.4000000059604645
        roughness: 0.25
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: gloss_material
        objectName: "GLOSS"
        baseColor: "#ff161619"
        metalness: 0.11999999731779099
        roughness: 0.2199999988079071
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: black_material
        objectName: "BLACK"
        baseColor: "#ff29292d"
        roughness: 0.5199999809265137
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: matte_material
        objectName: "MATTE"
        baseColor: "#ff222225"
        roughness: 0.8199999928474426
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: roof_material
        objectName: "ROOF"
        baseColor: "#ff141418"
        metalness: 0.20000000298023224
        roughness: 0.1599999964237213
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: paint_material
        objectName: "PAINT"
        baseColor: "#ffdcdedf"
        metalness: 0.6136999726295471
        roughness: 0.3840999901294708
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: interior_material
        objectName: "INTERIOR"
        baseColor: "#ff1c1c1f"
        metalness: 0.10000000149011612
        roughness: 0.8199999928474426
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: reverse_material
        objectName: "REVERSE"
        baseColor: "#ccededed"
        roughness: 0.20000000298023224
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }
    PrincipledMaterial {
        id: seat_material
        objectName: "SEAT"
        baseColor: "#ff1c1c1f"
        metalness: 0.09189999848604202
        roughness: 0.513700008392334
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: glass_material
        objectName: "GLASS"
        baseColor: "#d2171a1d"   // dl61: vetro fume'
        roughness: 0.05000000074505806
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
        metalness: 0.0
        specularAmount: 1.0
    }
    PrincipledMaterial {
        id: taildark_material
        objectName: "TAILDARK"
        baseColor: "#ff810d24"
        roughness: 0.44999998807907104
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: signal_material
        objectName: "SIGNAL"
        baseColor: "#f2ff8e27"
        roughness: 0.15000000596046448
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Blend
    }
    PrincipledMaterial {
        id: carpet_material
        objectName: "CARPET"
        baseColor: "#ff656565"
        metalness: 0.07129999995231628
        roughness: 0.8270999789237976
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Node {
        id: sketchfab_model
        objectName: "Sketchfab_model"
        rotation: Qt.quaternion(0.707107, -0.707107, 0, 0)
        scale: Qt.vector3d(1, 1, 1)
        Node {
            id: carGroup
            objectName: "CarGroup"
            Model {
                id: bodyshell_vehicle_generic_alloy_silver_spec__PAINT_1__in
                objectName: "bodyshell|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                source: "carbody_meshes/bodyshell_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_alloy_silver_spec__PAINT_1_
                objectName: "bodyshell|vehicle_generic_alloy_silver_spec__PAINT_1_"
                source: "carbody_meshes/bodyshell_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_alloy_silver_spec__PAINT_2_
                objectName: "bodyshell|vehicle_generic_alloy_silver_spec__PAINT_2_"
                source: "carbody_meshes/bodyshell_vehicle_generic_alloy_silver_spec__PAINT_2__mesh.mesh"
                materials: [
                    roof_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_doorshut__PAINT_2__in
                objectName: "bodyshell|vehicle_generic_doorshut__PAINT_2_|in"
                source: "carbody_meshes/bodyshell_vehicle_generic_doorshut__PAINT_2__in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_smallspecmap_BLACK_grl
                objectName: "bodyshell|vehicle_generic_smallspecmap|BLACK|grl"
                source: "carbody_meshes/bodyshell_vehicle_generic_smallspecmap_BLACK_grl_mesh.mesh"
                materials: [
                    matte_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_smallspecmap_BLACK
                objectName: "bodyshell|vehicle_generic_smallspecmap|BLACK"
                source: "carbody_meshes/bodyshell_vehicle_generic_smallspecmap_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: bodyshell_nodamage_PAINT_in
                objectName: "bodyshell|nodamage|PAINT|in"
                source: "carbody_meshes/bodyshell_nodamage_PAINT_in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bodyshell_nodamage_PAINT
                objectName: "bodyshell|nodamage|PAINT"
                source: "carbody_meshes/bodyshell_nodamage_PAINT_mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bodyshell_nodamage_BLACK
                objectName: "bodyshell|nodamage|BLACK"
                source: "carbody_meshes/bodyshell_nodamage_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: bodyshell_black
                objectName: "bodyshell|black"
                source: "carbody_meshes/bodyshell_black_mesh.mesh"
                materials: [
                    gloss_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_detail2_PAINT_in
                objectName: "bodyshell|vehicle_generic_detail2|PAINT|in"
                source: "carbody_meshes/bodyshell_vehicle_generic_detail2_PAINT_in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_detail2_BLACK_grl
                objectName: "bodyshell|vehicle_generic_detail2|BLACK|grl"
                source: "carbody_meshes/bodyshell_vehicle_generic_detail2_BLACK_grl_mesh.mesh"
                materials: [
                    matte_material
                ]
            }
            Model {
                id: bodyshell_vehicle_generic_detail2_BLACK
                objectName: "bodyshell|vehicle_generic_detail2|BLACK"
                source: "carbody_meshes/bodyshell_vehicle_generic_detail2_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: brakelight_l_lights_lod0
                objectName: "brakelight_l|lights_lod0"
                source: "carbody_meshes/brakelight_l_lights_lod0_mesh.mesh"
                materials: [
                    tailglass_material
                ]
            }
            Model {
                id: brakelight_l_lights_op
                objectName: "brakelight_l|lights_op"
                source: "carbody_meshes/brakelight_l_lights_op_mesh.mesh"
                materials: [
                    tailribu_material
                ]
            }
            Model {
                id: brakelight_r_lights_lod0
                objectName: "brakelight_r|lights_lod0"
                source: "carbody_meshes/brakelight_r_lights_lod0_mesh.mesh"
                materials: [
                    tailglass_material
                ]
            }
            Model {
                id: brakelight_r_lights_op
                objectName: "brakelight_r|lights_op"
                source: "carbody_meshes/brakelight_r_lights_op_mesh.mesh"
                materials: [
                    tailribu_material
                ]
            }
            Model {
                id: bumper_f_vehicle_generic_alloy_silver_spec__PAINT_1_
                objectName: "bumper_f|vehicle_generic_alloy_silver_spec__PAINT_1_"
                source: "carbody_meshes/bumper_f_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bumper_f_vehicle_generic_smallspecmap_BLACK_grl
                objectName: "bumper_f|vehicle_generic_smallspecmap|BLACK|grl"
                source: "carbody_meshes/bumper_f_vehicle_generic_smallspecmap_BLACK_grl_mesh.mesh"
                materials: [
                    matte_material
                ]
            }
            Model {
                id: bumper_f_nodamage_PAINT
                objectName: "bumper_f|nodamage|PAINT"
                source: "carbody_meshes/bumper_f_nodamage_PAINT_mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bumper_f_nodamage_BLACK_grl
                objectName: "bumper_f|nodamage|BLACK|grl"
                source: "carbody_meshes/bumper_f_nodamage_BLACK_grl_mesh.mesh"
                materials: [
                    matte_material
                ]
            }
            Model {
                id: bumper_f_nodamage_BLACK
                objectName: "bumper_f|nodamage|BLACK"
                source: "carbody_meshes/bumper_f_nodamage_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: bumper_r_vehicle_generic_alloy_silver_spec__PAINT_1__in
                objectName: "bumper_r|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                source: "carbody_meshes/bumper_r_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bumper_r_vehicle_generic_alloy_silver_spec__PAINT_1_
                objectName: "bumper_r|vehicle_generic_alloy_silver_spec__PAINT_1_"
                source: "carbody_meshes/bumper_r_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bumper_r_nodamage_PAINT_in
                objectName: "bumper_r|nodamage|PAINT|in"
                source: "carbody_meshes/bumper_r_nodamage_PAINT_in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: bumper_r_nodamage_PAINT
                objectName: "bumper_r|nodamage|PAINT"
                source: "carbody_meshes/bumper_r_nodamage_PAINT_mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: bumper_r_nodamage_BLACK
                objectName: "bumper_r|nodamage|BLACK"
                source: "carbody_meshes/bumper_r_nodamage_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: chassis_vehicle_generic_smallspecmap
                objectName: "chassis|vehicle_generic_smallspecmap"
                source: "carbody_meshes/chassis_vehicle_generic_smallspecmap_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: chassis_wood
                objectName: "chassis|wood"
                source: "carbody_meshes/chassis_wood_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: chassis_interior_lod0_carpet
                objectName: "chassis|interior_lod0|carpet"
                source: "carbody_meshes/chassis_interior_lod0_carpet_mesh.mesh"
                materials: [
                    carpet_material
                ]
            }
            Model {
                id: chassis_interior_lod0
                objectName: "chassis|interior_lod0"
                source: "carbody_meshes/chassis_interior_lod0_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: chassis_display
                objectName: "chassis|display"
                source: "carbody_meshes/chassis_display_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: dials_script_rt_dials_cavalcade
                objectName: "dials|script_rt_dials_cavalcade"
                source: "carbody_meshes/dials_script_rt_dials_cavalcade_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: indicator_lf_lights_lod0
                objectName: "indicator_lf|lights_lod0"
                source: "carbody_meshes/indicator_lf_lights_lod0_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: indicator_lr_lights_lod0
                objectName: "indicator_lr|lights_lod0"
                source: "carbody_meshes/indicator_lr_lights_lod0_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: indicator_lr_lights_op
                objectName: "indicator_lr|lights_op"
                source: "carbody_meshes/indicator_lr_lights_op_mesh.mesh"
                materials: [
                    taildark_material
                ]
            }
            Model {
                id: indicator_rf_lights_lod0
                objectName: "indicator_rf|lights_lod0"
                source: "carbody_meshes/indicator_rf_lights_lod0_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: indicator_rr_lights_lod0
                objectName: "indicator_rr|lights_lod0"
                source: "carbody_meshes/indicator_rr_lights_lod0_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: indicator_rr_lights_op
                objectName: "indicator_rr|lights_op"
                source: "carbody_meshes/indicator_rr_lights_op_mesh.mesh"
                materials: [
                    taildark_material
                ]
            }
            Model {
                id: reversinglight_l_lights_lod0
                objectName: "reversinglight_l|lights_lod0"
                source: "carbody_meshes/reversinglight_l_lights_lod0_mesh.mesh"
                materials: [
                    reverse_material
                ]
            }
            Model {
                id: reversinglight_r_lights_lod0
                objectName: "reversinglight_r|lights_lod0"
                source: "carbody_meshes/reversinglight_r_lights_lod0_mesh.mesh"
                materials: [
                    reverse_material
                ]
            }
            Model {
                id: sedili_interior_lod0
                objectName: "sedili|interior_lod0"
                source: "carbody_meshes/sedili_interior_lod0_mesh.mesh"
                materials: [
                    seat_material
                ]
            }
            Model {
                id: steeringwheel_interior_lod0
                objectName: "steeringwheel|interior_lod0"
                source: "carbody_meshes/steeringwheel_interior_lod0_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: taillight_l_lights_lod0
                objectName: "taillight_l|lights_lod0"
                source: "carbody_meshes/taillight_l_lights_lod0_mesh.mesh"
                materials: [
                    tailglass_material
                ]
            }
            Model {
                id: taillight_l_lights_op
                objectName: "taillight_l|lights_op"
                source: "carbody_meshes/taillight_l_lights_op_mesh.mesh"
                materials: [
                    tailribu_material
                ]
            }
            Model {
                id: taillight_r_lights_lod0
                objectName: "taillight_r|lights_lod0"
                source: "carbody_meshes/taillight_r_lights_lod0_mesh.mesh"
                materials: [
                    tailglass_material
                ]
            }
            Model {
                id: taillight_r_lights_op
                objectName: "taillight_r|lights_op"
                source: "carbody_meshes/taillight_r_lights_op_mesh.mesh"
                materials: [
                    tailribu_material
                ]
            }
            Model {
                id: windscreen_f_vehicle_generic_glasswindows2
                objectName: "windscreen_f|vehicle_generic_glasswindows2"
                source: "carbody_meshes/windscreen_f_vehicle_generic_glasswindows2_mesh.mesh"
                materials: [
                    glass_material
                ]
            }
            Model {
                id: wing_lf_vehicle_generic_alloy_silver_spec__PAINT_1__in
                objectName: "wing_lf|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                source: "carbody_meshes/wing_lf_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: wing_lf_vehicle_generic_alloy_silver_spec__PAINT_1_
                objectName: "wing_lf|vehicle_generic_alloy_silver_spec__PAINT_1_"
                source: "carbody_meshes/wing_lf_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: wing_lf_vehicle_generic_smallspecmap
                objectName: "wing_lf|vehicle_generic_smallspecmap"
                source: "carbody_meshes/wing_lf_vehicle_generic_smallspecmap_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: wing_lf_lights_lod0
                objectName: "wing_lf|lights_lod0"
                source: "carbody_meshes/wing_lf_lights_lod0_mesh.mesh"
                materials: [
                    tailred_material
                ]
            }
            Model {
                id: wing_lf_vehicle_generic_glasswindows2
                objectName: "wing_lf|vehicle_generic_glasswindows2"
                source: "carbody_meshes/wing_lf_vehicle_generic_glasswindows2_mesh.mesh"
                materials: [
                    glass_material
                ]
            }
            Model {
                id: wing_lf_nodamage
                objectName: "wing_lf|nodamage"
                source: "carbody_meshes/wing_lf_nodamage_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: wing_rf_vehicle_generic_alloy_silver_spec__PAINT_1__in
                objectName: "wing_rf|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                source: "carbody_meshes/wing_rf_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                materials: [
                    interior_material
                ]
            }
            Model {
                id: wing_rf_vehicle_generic_alloy_silver_spec__PAINT_1_
                objectName: "wing_rf|vehicle_generic_alloy_silver_spec__PAINT_1_"
                source: "carbody_meshes/wing_rf_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Model {
                id: wing_rf_vehicle_generic_smallspecmap
                objectName: "wing_rf|vehicle_generic_smallspecmap"
                source: "carbody_meshes/wing_rf_vehicle_generic_smallspecmap_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: wing_rf_lights_lod0
                objectName: "wing_rf|lights_lod0"
                source: "carbody_meshes/wing_rf_lights_lod0_mesh.mesh"
                materials: [
                    tailred_material
                ]
            }
            Model {
                id: wing_rf_vehicle_generic_glasswindows2
                objectName: "wing_rf|vehicle_generic_glasswindows2"
                source: "carbody_meshes/wing_rf_vehicle_generic_glasswindows2_mesh.mesh"
                materials: [
                    glass_material
                ]
            }
            Model {
                id: wing_rf_nodamage
                objectName: "wing_rf|nodamage"
                source: "carbody_meshes/wing_rf_nodamage_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: smart_headlight_L_vivace_glass_HLGLASS
                objectName: "smart_headlight_L|vivace_glass|HLGLASS"
                source: "carbody_meshes/smart_headlight_L_vivace_glass_HLGLASS_mesh.mesh"
                materials: [
                    hlglass_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_signal_L_SIGNAL
                objectName: "smart_headlight_L|smart_signal_L|SIGNAL"
                source: "carbody_meshes/smart_headlight_L_smart_signal_L_SIGNAL_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_lowbeam_BULB
                objectName: "smart_headlight_L|smart_lowbeam|BULB"
                source: "carbody_meshes/smart_headlight_L_smart_lowbeam_BULB_mesh.mesh"
                materials: [
                    bulb_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_chrome3_REFL
                objectName: "smart_headlight_L|smart_chrome3|REFL"
                source: "carbody_meshes/smart_headlight_L_smart_chrome3_REFL_mesh.mesh"
                materials: [
                    refl_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_black_BLACK
                objectName: "smart_headlight_L|smart_black|BLACK"
                source: "carbody_meshes/smart_headlight_L_smart_black_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_signalframe_L_HOUSING
                objectName: "smart_headlight_L|smart_signalframe_L|HOUSING"
                source: "carbody_meshes/smart_headlight_L_smart_signalframe_L_HOUSING_mesh.mesh"
                materials: [
                    housing_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_highbeam_BULB
                objectName: "smart_headlight_L|smart_highbeam|BULB"
                source: "carbody_meshes/smart_headlight_L_smart_highbeam_BULB_mesh.mesh"
                materials: [
                    bulb_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_highbeamframe_HLCHROME
                objectName: "smart_headlight_L|smart_highbeamframe|HLCHROME"
                source: "carbody_meshes/smart_headlight_L_smart_highbeamframe_HLCHROME_mesh.mesh"
                materials: [
                    hlchrome_material
                ]
            }
            Model {
                id: smart_headlight_L_smart_lowbeamframe_HLCHROME
                objectName: "smart_headlight_L|smart_lowbeamframe|HLCHROME"
                source: "carbody_meshes/smart_headlight_L_smart_lowbeamframe_HLCHROME_mesh.mesh"
                materials: [
                    hlchrome_material
                ]
            }
            Model {
                id: smart_headlight_R_vivace_glass_HLGLASS
                objectName: "smart_headlight_R|vivace_glass|HLGLASS"
                source: "carbody_meshes/smart_headlight_R_vivace_glass_HLGLASS_mesh.mesh"
                materials: [
                    hlglass_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_signal_R_SIGNAL
                objectName: "smart_headlight_R|smart_signal_R|SIGNAL"
                source: "carbody_meshes/smart_headlight_R_smart_signal_R_SIGNAL_mesh.mesh"
                materials: [
                    signal_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_lowbeam_BULB
                objectName: "smart_headlight_R|smart_lowbeam|BULB"
                source: "carbody_meshes/smart_headlight_R_smart_lowbeam_BULB_mesh.mesh"
                materials: [
                    bulb_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_chrome3_REFL
                objectName: "smart_headlight_R|smart_chrome3|REFL"
                source: "carbody_meshes/smart_headlight_R_smart_chrome3_REFL_mesh.mesh"
                materials: [
                    refl_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_black_BLACK
                objectName: "smart_headlight_R|smart_black|BLACK"
                source: "carbody_meshes/smart_headlight_R_smart_black_BLACK_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_signalframe_R_HOUSING
                objectName: "smart_headlight_R|smart_signalframe_R|HOUSING"
                source: "carbody_meshes/smart_headlight_R_smart_signalframe_R_HOUSING_mesh.mesh"
                materials: [
                    housing_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_highbeam_BULB
                objectName: "smart_headlight_R|smart_highbeam|BULB"
                source: "carbody_meshes/smart_headlight_R_smart_highbeam_BULB_mesh.mesh"
                materials: [
                    bulb_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_highbeamframe_HLCHROME
                objectName: "smart_headlight_R|smart_highbeamframe|HLCHROME"
                source: "carbody_meshes/smart_headlight_R_smart_highbeamframe_HLCHROME_mesh.mesh"
                materials: [
                    hlchrome_material
                ]
            }
            Model {
                id: smart_headlight_R_smart_lowbeamframe_HLCHROME
                objectName: "smart_headlight_R|smart_lowbeamframe|HLCHROME"
                source: "carbody_meshes/smart_headlight_R_smart_lowbeamframe_HLCHROME_mesh.mesh"
                materials: [
                    hlchrome_material
                ]
            }
            Model {
                id: roof_cad_ROOF
                objectName: "roof_cad|ROOF"
                source: "carbody_meshes/roof_cad_ROOF_mesh.mesh"
                materials: [
                    roof_material
                ]
            }
            Model {
                id: smart_sillstrip_L_strip_GLOSS
                objectName: "smart_sillstrip_L|strip|GLOSS"
                source: "carbody_meshes/smart_sillstrip_L_strip_GLOSS_mesh.mesh"
                materials: [
                    gloss_material
                ]
            }
            Model {
                id: smart_sillstrip_R_strip_GLOSS
                objectName: "smart_sillstrip_R|strip|GLOSS"
                source: "carbody_meshes/smart_sillstrip_R_strip_GLOSS_mesh.mesh"
                materials: [
                    gloss_material
                ]
            }
            Model {
                id: fill_lowgrille
                objectName: "fill_lowgrille"
                source: "carbody_meshes/fill_lowgrille_mesh.mesh"
                materials: [
                    black_material
                ]
            }
            Model {
                id: bumper_f_lipband
                objectName: "bumper_f|lipband"
                source: "carbody_meshes/bumper_f_lipband_mesh.mesh"
                materials: [
                    paint_material
                ]
            }
            Node {
                id: doorR
                objectName: "DoorR"
                position: Qt.vector3d(0.685062, -0.560023, 0)
                Model {
                    id: door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_1__in
                    objectName: "door_dside_f|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_1_
                    objectName: "door_dside_f|vehicle_generic_alloy_silver_spec__PAINT_1_"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                    materials: [
                        paint_material
                    ]
                }
                Model {
                    id: door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_2_
                    objectName: "door_dside_f|vehicle_generic_alloy_silver_spec__PAINT_2_"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_vehicle_generic_alloy_silver_spec__PAINT_2__mesh.mesh"
                    materials: [
                        matte_material
                    ]
                }
                Model {
                    id: door_dside_f_vehicle_generic_smallspecmap
                    objectName: "door_dside_f|vehicle_generic_smallspecmap"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_vehicle_generic_smallspecmap_mesh.mesh"
                    materials: [
                        matte_material
                    ]
                }
                Model {
                    id: door_dside_f_nodamage
                    objectName: "door_dside_f|nodamage"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_nodamage_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: door_dside_f_wood
                    objectName: "door_dside_f|wood"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_wood_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: door_dside_f_interior_lod0
                    objectName: "door_dside_f|interior_lod0"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_dside_f_interior_lod0_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: window_lf_vehicle_generic_glasswindows2
                    objectName: "window_lf|vehicle_generic_glasswindows2"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/window_lf_vehicle_generic_glasswindows2_mesh.mesh"
                    materials: [
                        glass_material
                    ]
                }
                Model {
                    id: window_lm_vehicle_generic_glasswindows2
                    objectName: "window_lm|vehicle_generic_glasswindows2"
                    position: Qt.vector3d(-0.685062, 0.560023, 0)
                    source: "carbody_meshes/window_lm_vehicle_generic_glasswindows2_mesh.mesh"
                    materials: [
                        glass_material
                    ]
                }
            }
            Node {
                id: doorL
                objectName: "DoorL"
                position: Qt.vector3d(-0.685062, -0.560023, 0)
                Model {
                    id: door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_1__in
                    objectName: "door_pside_f|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_1_
                    objectName: "door_pside_f|vehicle_generic_alloy_silver_spec__PAINT_1_"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                    materials: [
                        paint_material
                    ]
                }
                Model {
                    id: door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_2_
                    objectName: "door_pside_f|vehicle_generic_alloy_silver_spec__PAINT_2_"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_vehicle_generic_alloy_silver_spec__PAINT_2__mesh.mesh"
                    materials: [
                        matte_material
                    ]
                }
                Model {
                    id: door_pside_f_vehicle_generic_smallspecmap
                    objectName: "door_pside_f|vehicle_generic_smallspecmap"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_vehicle_generic_smallspecmap_mesh.mesh"
                    materials: [
                        matte_material
                    ]
                }
                Model {
                    id: door_pside_f_nodamage
                    objectName: "door_pside_f|nodamage"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_nodamage_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: door_pside_f_wood
                    objectName: "door_pside_f|wood"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_wood_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: door_pside_f_interior_lod0
                    objectName: "door_pside_f|interior_lod0"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/door_pside_f_interior_lod0_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: window_rf_vehicle_generic_glasswindows2
                    objectName: "window_rf|vehicle_generic_glasswindows2"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/window_rf_vehicle_generic_glasswindows2_mesh.mesh"
                    materials: [
                        glass_material
                    ]
                }
                Model {
                    id: window_rm_vehicle_generic_glasswindows2
                    objectName: "window_rm|vehicle_generic_glasswindows2"
                    position: Qt.vector3d(0.685062, 0.560023, 0)
                    source: "carbody_meshes/window_rm_vehicle_generic_glasswindows2_mesh.mesh"
                    materials: [
                        glass_material
                    ]
                }
            }
            Node {
                id: hatch
                objectName: "Hatch"
                position: Qt.vector3d(0, 0.931495, 1.47539)
                Model {
                    id: bonnet_vehicle_generic_smallspecmap
                    objectName: "bonnet|vehicle_generic_smallspecmap"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/bonnet_vehicle_generic_smallspecmap_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: bonnet_nodamage
                    objectName: "bonnet|nodamage"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/bonnet_nodamage_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: bonnet_black
                    objectName: "bonnet|black"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/bonnet_black_mesh.mesh"
                    materials: [
                        gloss_material
                    ]
                }
                Model {
                    id: bonnet_interior_lod0
                    objectName: "bonnet|interior_lod0"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/bonnet_interior_lod0_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: windscreen_r_vehicle_generic_glasswindows2
                    objectName: "windscreen_r|vehicle_generic_glasswindows2"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/windscreen_r_vehicle_generic_glasswindows2_mesh.mesh"
                    materials: [
                        glass_material
                    ]
                }
                Model {
                    id: brakelight_m_panto_lights
                    objectName: "brakelight_m|panto_lights"
                    position: Qt.vector3d(0, -0.931495, -1.47539)
                    source: "carbody_meshes/brakelight_m_panto_lights_mesh.mesh"
                    materials: [
                        tailred_material
                    ]
                }
            }
            Node {
                id: flap
                objectName: "Flap"
                position: Qt.vector3d(0, 1.22, 0.7)
                Model {
                    id: boot_vehicle_generic_alloy_silver_spec__PAINT_1__in
                    objectName: "boot|vehicle_generic_alloy_silver_spec__PAINT_1_|in"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_vehicle_generic_alloy_silver_spec__PAINT_1__in_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: boot_vehicle_generic_alloy_silver_spec__PAINT_1_
                    objectName: "boot|vehicle_generic_alloy_silver_spec__PAINT_1_"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_vehicle_generic_alloy_silver_spec__PAINT_1__mesh.mesh"
                    materials: [
                        paint_material
                    ]
                }
                Model {
                    id: boot_vehicle_generic_smallspecmap
                    objectName: "boot|vehicle_generic_smallspecmap"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_vehicle_generic_smallspecmap_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: boot_nodamage
                    objectName: "boot|nodamage"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_nodamage_mesh.mesh"
                    materials: [
                        black_material
                    ]
                }
                Model {
                    id: boot_interior_lod0
                    objectName: "boot|interior_lod0"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_interior_lod0_mesh.mesh"
                    materials: [
                        interior_material
                    ]
                }
                Model {
                    id: boot_vehicle_genericmud_car
                    objectName: "boot|vehicle_genericmud_car"
                    position: Qt.vector3d(0, -1.22, -0.7)
                    source: "carbody_meshes/boot_vehicle_genericmud_car_mesh.mesh"
                    materials: [
                        paint_material
                    ]
                }
            }
        }
    }

    // Animations:
}
