class_name ProceduralMeshFactory
extends RefCounted

## Original, project-created procedural mesh/material helpers (P39). No
## external mesh/texture files are ever imported — every 3D shape in the
## game is either this kind of code-generated primitive or (once P40 adds
## real character art) an authored project asset. Naming convention: see
## "Asset naming convention" in docs/design/ART_ASSET_LIST.md. Routing
## every ad-hoc BoxMesh/StandardMaterial3D construction through here keeps
## tinting/roughness consistent instead of scattering magic numbers across
## scene scripts.

const DEFAULT_ROUGHNESS: float = 0.82

static func make_material(color: Color, roughness: float = DEFAULT_ROUGHNESS, metallic: float = 0.0) -> StandardMaterial3D:
    var mat: StandardMaterial3D = StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.metallic = metallic
    if color.a < 1.0:
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return mat

## node_name follows the project's asset naming convention: PascalCase,
## no spaces (e.g. "ServerRackBody").
static func make_box(node_name: String, size: Vector3, color: Color, roughness: float = DEFAULT_ROUGHNESS) -> MeshInstance3D:
    var mi: MeshInstance3D = MeshInstance3D.new()
    mi.name = node_name
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mesh.material = make_material(color, roughness)
    mi.mesh = mesh
    return mi

static func make_capsule(node_name: String, radius: float, height: float, color: Color, roughness: float = 0.7) -> MeshInstance3D:
    var mi: MeshInstance3D = MeshInstance3D.new()
    mi.name = node_name
    var mesh: CapsuleMesh = CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.material = make_material(color, roughness)
    mi.mesh = mesh
    return mi

static func make_cylinder(node_name: String, top_radius: float, bottom_radius: float, height: float, color: Color, roughness: float = DEFAULT_ROUGHNESS) -> MeshInstance3D:
    var mi: MeshInstance3D = MeshInstance3D.new()
    mi.name = node_name
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = top_radius
    mesh.bottom_radius = bottom_radius
    mesh.height = height
    mesh.material = make_material(color, roughness)
    mi.mesh = mesh
    return mi
