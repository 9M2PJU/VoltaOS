import QtQuick
import QtQuick3D

Node {
    id: node

    // Resources
    PrincipledMaterial {
        id: matte_material
        objectName: "MATTE"
        baseColor: "#ff212124"
        roughness: 0.9200000166893005
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: hubblk_material
        objectName: "HUBBLK"
        baseColor: "#ff1c1c1f"
        roughness: 0.8999999761581421
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: tyre_material
        objectName: "TYRE"
        baseColor: "#ff1c1c1c"
        roughness: 0.8999999761581421
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: rim_material
        objectName: "RIM"
        baseColor: "#ffced0d3"
        metalness: 1
        roughness: 0.2800000011920929
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: disc_material
        objectName: "DISC"
        baseColor: "#ff767679"
        metalness: 0.800000011920929
        roughness: 0.44999998807907104
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }
    PrincipledMaterial {
        id: caliper_material
        objectName: "CALIPER"
        baseColor: "#ff1c1c1f"
        metalness: 0.20000000298023224
        roughness: 0.3499999940395355
        cullMode: PrincipledMaterial.NoCulling
        alphaMode: PrincipledMaterial.Opaque
    }

    // Nodes:
    Node {
        id: root
        objectName: "ROOT"
        Model {
            id: brake_assembly
            objectName: "brake assembly"
            source: "carwheel_meshes/brake_assembly_001_mesh.mesh"
            materials: [
                matte_material
            ]
        }
        Model {
            id: tube52
            objectName: "Tube52"
            source: "carwheel_meshes/tube52_001_mesh.mesh"
            materials: [
                matte_material
            ]
        }
        Model {
            id: tube223
            objectName: "Tube223"
            source: "carwheel_meshes/tube223_001_mesh.mesh"
            materials: [
                hubblk_material
            ]
        }
        Model {
            id: object31
            objectName: "Object31"
            source: "carwheel_meshes/object31_001_mesh.mesh"
            materials: [
                tyre_material
            ]
        }
        Model {
            id: obj_Plane03
            objectName: "Obj_Plane03"
            source: "carwheel_meshes/obj_Plane03_mesh.mesh"
            materials: [
                rim_material,
                hubblk_material
            ]
        }
        Model {
            id: brake_disk
            objectName: "brake disk"
            source: "carwheel_meshes/brake_disk_001_mesh.mesh"
            materials: [
                disc_material
            ]
        }
        Model {
            id: brake_disk07
            objectName: "brake disk07"
            source: "carwheel_meshes/brake_disk07_001_mesh.mesh"
            materials: [
                caliper_material
            ]
        }
    }

    // Animations:
}
