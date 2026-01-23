# How to Create a Painterly Shader Material & Export Color and Normal Maps in Blender

## Prerequisites

**First, make sure your model is UV unwrapped.**

- Edit mode (Tab) > Press `U` > **Smart UV Project** or **Unwrap**
a
---

## Part 1: Creating the Painterly Shader Material

### Step 1: Set Up Your Base Material

1. Select your model
2. Go to **Shading** workspace
3. Click **New** to create a material (if needed)

### Step 2: Build the Painterly Node Setup

- Drag **Voronoi Texture** `Position` socket out of `Normal` socket of **Principled BSDF** node
  - Set scale of VT to 2.2
- Drag **Vector Math: Add** out of `Vector` Socket of **Voronoi Texture** node
  - Drag **Geometry** `Normal` socket out of *top* `Vector` Socket of **Add** node
  - Drag **Vector Math: Scale** out of *bottom* `Vector` Socket of **Add** node
    - Set scale to 1.5
- Drag **Vector Math: Subtract** out of `Vector` Socket of **Scale** node
  - Set *bottom* Vector's values to 0.5
  - Drag **Noise Texture** `Color` socket out of *top* `Vector` Socket of **Subtract** node
    - Set scale to 4.5
- Drag **Texture Coordinate** `Object` socket out of **Noise Texture** `Vector` node

- Add **Image Texture** Node for *NORMALS*
  - New (name + set resolution)
  - Drag **UV Map** out of `Vector` Socket of **Image Texture** node

TBD for existing textures. Maybe just add **UV Map**?

- Add **Image Texture** Node for *COLORS*
  - New (name + set resolution)
  - Drag **UV Map** out of `Vector` Socket of **Image Texture** node

---

**DON"T TRUST BELOW YET**

NORMALS
Click Normals Image Texture in graph editor
1. **Render Properties** > Change to **Cycles** engine
2. Scroll to **Bake** section
3. **Bake Type:** **Normal**
4. Click Bake
5. **Image** pane, **Image **> **Save As** > Save as PNG

---

## Part 3: Exporting the Color Map

### Step 1: Add Another Image Texture Node

1. Add second **Image Texture** node (don't connect it)
2. Click **New**, name it `ColorMap_Bake`
3. Set same resolution as normal map
4. **Select this node**

### Step 2: Configure & Bake

1. **Bake Type:** **Diffuse**
2. Uncheck **Direct** and **Indirect**
3. Click **Bake**
4. **Image** > **Save As** > Save as PNG: `YourModel_Color.png`

---

## Part 4: Export Model to GLB

1. **File** > **Export** > **glTF 2.0 (.glb/.gltf)**
2. Choose **Format: glTF Binary (.glb)**
3. Check **Apply Modifiers** if needed
4. Click **Export glTF 2.0**

---

## Part 5: Import to Godot

### Step 1: Import Files

1. Copy `.glb` file and textures to your Godot project folder
2. Wait for auto-import

### Step 2: Add Model to Scene

1. Drag `.glb` file into your scene
2. Expand the imported model nodes
3. Find the **MeshInstance3D** node

### Step 3: Create StandardMaterial3D

1. In Inspector, find **Material** section
2. **Surface Material Override** > **New StandardMaterial3D**
3. Click the material to edit

### Step 4: Assign Textures

**Albedo (Color):**

1. Expand **Albedo** section
2. Enable **Texture**
3. **Load** > Select `YourModel_Color.png`

**Normal Map:**

1. Expand **Normal Map** section
2. Enable **Normal Map**
3. **Load** > Select `YourModel_Normal.png`
4. Adjust **Normal Scale** if needed (default 1.0)

### Step 5: Adjust Settings (Optional)

- **Metallic:** 0.0 for non-metallic
- **Roughness:** Adjust shininess (0.0 = mirror, 1.0 = matte)

---

## Quick Troubleshooting

**Blender:**

- Normal map flat? Check **Tangent** space and UV unwrapping
- Bake greyed out? Switch to Cycles and select Image Texture node

**Godot:**

- Model black? Check material is assigned to MeshInstance3D
- No normal effect? Enable Normal Map and check Normal Scale
- Too dark? Add DirectionalLight3D to scene
