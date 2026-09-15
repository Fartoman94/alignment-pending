# Art Bible — Original 3D identity

## Visual thesis
A cheerful, tactile corporate diorama slowly becomes an intimidating machine campus. Low-poly geometry, crisp silhouettes, limited materials, readable at isometric distance.

## Important originality rule
The phrase “early-2000s life-sim feel” means technological mood only. Do **not** reproduce any specific game's character proportions, iconic indicators, wall-cutaway behavior, UI panels, cursor, furniture designs, textures, fonts, sound cues, animations, or camera timings.

## Geometry
- Characters: 800–2,500 triangles for main staff LOD0.
- Props: 50–2,000 triangles.
- Buildings: modular wall/floor kits.
- Mostly flat-shaded or lightly smoothed surfaces.
- Beveled corners only where silhouette benefits.

## Character language
- Slightly oversized head/hands for readability, but not caricatures of known franchises.
- Faceted torso/limbs.
- Swappable hair/clothing/accessory meshes.
- Faces use minimal original texture atlas: brows, eyes, mouth variants.
- Emotions shown by posture + small overhead status glyphs.

## Environment progression
1. Cheap converted office: mismatched desks, exposed cables, humming rack.
2. Venture office: glass meeting rooms, branded wall, dedicated lab.
3. Campus: security gates, compute rooms, media studio.
4. Infrastructure era: remote datacenter map and power facilities.

## Palette
Base corporate: charcoal, warm gray, off-white. Gameplay accent families are semantically assigned:
- Capability: electric violet
- Safety: cyan/teal
- Trust: warm gold
- Risk: coral/red
- Money: green
- Compute: blue

Ensure colorblind-safe icon/shape redundancy.

## Lighting
Soft directional key + baked/SSIL-friendly ambient look. Night office uses monitor pools and emergency lights. Avoid photorealism.

## Asset creation policy
Create meshes procedurally in Godot, by original Blender scripts, or by artists under project ownership. Every final asset must have an entry in `docs/legal/ASSET_PROVENANCE.md`.
