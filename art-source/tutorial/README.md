# Tutorial pointing arm

## Reference contract

- Source of truth: `memory/ART_DIRECTION.md` white-sleeved hand update (2026-10-18).
- Reference images, visually inspected: `assets/image/machine-layered/target-arm-open.png` and `target-arm-grip.png` (both 160 × 80, transparent).
- Keep the same warm pale skin, long loose ivory/white robe sleeve, dark brown/black outline, coarse pixel clusters, restrained two/three-tone shading, and right-to-left arm direction.
- New pose only: one extended index finger points left; other fingers naturally curl into the palm, thumb rests against the curled fingers.
- Deliver one arm, transparent alpha, no scene, text, arrows, bubble, or props.
- Production file: `assets/image/tutorial/god-arm-point.png`. Preserve the original generated PNG and alpha; rendering handles size and rotation.

## Generation

Built-in image generation, reference-guided pose variation. Reference images are identity/style references, not replacement targets.

### Final prompt

Use case: stylized-concept.
Asset type: transparent pixel-art game tutorial pointer sprite.
Input image 1 and image 2 are identity, costume, palette and pixel-style references of the same God's arm. Generate a NEW single pose of exactly this arm. Preserve the warm pale skin, very long loose ivory white robe sleeve, charcoal/dark-brown outline and sparse blocky beige-gray sleeve folds from the reference sprites. The sleeve enters from the RIGHT edge and the hand points horizontally LEFT. Extend only the index finger straight toward the left with its fingertip unmistakably visible; thumb rests against the other three naturally curled fingers. Show the back/side of the hand in the same viewpoint as the references. Retain the source sprite's coarse, low-native-resolution pixel clusters, simple 1-source-pixel dark outline and flat 2–3 shade groups. No antialiasing, soft gradients, painterly texture or extra detail. Single arm only, no shoulder/body/head. Wide 2:1 sprite framing, long sleeve occupying the right half, generous transparent space around the silhouette and no cropped fingers. True transparent RGBA background. No text, arrows, bubble, glow, detached shapes, shadow on the background or other objects.

## Visual QA

- Generated with the built-in image tool, then opened locally with `view_image` for reference comparison.
- Confirmed: a single connected arm; clear extended index finger pointing left; three curled fingers and resting thumb; long ivory sleeve with dark pixel outline; warm pale skin; no text, arrow, extra scene or bubble.
- Costume, low-resolution pixel clusters and sparse sleeve folds follow both reference sprites. No new costume, jewelry or trim introduced.
- The generated PNG is **1774 × 887**, 32-bit RGBA. The corner alpha is 0. It was copied byte-for-byte to production; no resampling, cropping, alpha removal or retouching.
- Generated source retained at `C:/Users/qinmy/.codex/generated_images/01a14f38-1f7b-7712-ac85-ee1e57b5b626/exec-cf3a22dc-1772-4238-90e9-342a2d3626a5.png`.
- Sprite coordinates: fingertip approximately **(0.125, 0.327)** of full image; native pointing direction is **(-1, 0)**. Drawing at a 160 × 80 design size preserves the 2:1 canvas ratio. Anchor the pointer at the fingertip before rotation.
- Rendering and in-game lighting/scale are owned by the tutorial overlay implementation and require full-scene verification.

## Opening monologue finger-heart arm

### Reference contract

- User requested the opening monologue hand to make a **single-hand finger heart** and emerge from below the game screen.
- Re-inspected the two original white-sleeve sprites and `god-arm-point.png` before generation. These three images are identity, costume, palette and pixel-cluster references.
- Preserve warm pale skin, long loose ivory/white robe sleeve, dark brown/black outline and restrained beige/gray sleeve folds.
- New pose: thumb and index cross at their tips to make the familiar small finger-heart gesture; the other three fingers curl naturally. One hand, five fingers total.
- Vertical framing: gesture at the top, long sleeve extending continuously through the bottom canvas edge. No floating sleeve end, heart icon, text, glow, scenery or second hand.
- Production destination: `assets/image/tutorial/god-arm-heart.png`. Keep generated PNG and its transparent alpha unchanged.

### Generation prompt

Use case: stylized-concept. Asset type: transparent pixel-art game character gesture sprite for an opening tutorial monologue. The three input images are identity, costume, skin-palette and pixel-art style references of the same God's arm. Generate a NEW pose of exactly this white-sleeved arm, keeping the same warm pale skin, long loose ivory white robe sleeve, charcoal/dark-brown outline and sparse blocky beige-gray sleeve folds. One single hand makes the recognizable small Korean finger-heart gesture: the index finger and thumb cross at their tips near the top of the hand, the other three fingers curl naturally into the palm; five fingers total. Palm/front three-quarter view so the thumb/index crossing is easy to read. The hand is at the TOP and the long arm/sleeve rises from BELOW. Vertical 2:3 canvas, gesture centered near (0.50, 0.25), forearm straight downward from the wrist. Give the sleeve a long continuous lower section extending all the way THROUGH THE BOTTOM EDGE: the sleeve is visibly cropped by the canvas bottom, not a floating closed-off stump and not a sleeve cuff at the bottom. Keep transparent margins to the left/right and above the fingers, all fingers fully visible. Preserve coarse low-native-resolution pixel clusters equivalent to an approximately 96 by 144 pixel sprite, hard stepped edges, simple dark outline, flat 2–3 shade groups, no antialiasing, soft gradients or painterly texture. True transparent RGBA background. No text, arrows, bubbles, heart-shaped icon, sparkles, glow, props, head, body, second hand or background shadow.

### Visual QA

- Generated with the built-in image tool and reopened locally using `view_image`.
- Confirmed one single-hand finger-heart pose: crossed thumb and index at the top, three curled fingers, one connected wrist and long white sleeve entering through the bottom edge. No heart icon, extra hand, text, props or costume additions.
- Warm pale skin, dark stepped outline, simple pixel clusters and ivory sleeve folds match the existing hand family.
- Production PNG: **1024 × 1536**, RGBA, copied byte-for-byte without editing or resampling. Sampled surrounding pixels have alpha **0**, including positions whose hidden RGB contains a brown halo; the hidden RGB is transparent and must remain ignored during alpha blending.
- Visible subject bounds at alpha > 127: **(258, 125) to (897, 1535)**, inclusive. Normalized bounds approximately **(0.252, 0.081) to (0.876, 1.000)**. The sleeve continues through the bottom edge.
- Thumb/index crossing (gesture focal point) approximately **(0.455, 0.145)**. Full visible hand center approximately **(0.48, 0.25)**.
- Recommended initial display size: **160 × 240 design pixels**, preserving the 2:3 canvas; the visible hand is about 47–50 design pixels wide at that size. Bottom of the sleeve should sit below the game-screen edge; animate upward from below without exposing a sleeve cut end.
- Source retained at `C:/Users/qinmy/.codex/generated_images/01a14f38-1f7b-7712-ac85-ee1e57b5b626/exec-2eb3e4f0-c016-44fb-9756-71895eae5e58.png`.
- Full-screen opening layout, alpha blending and motion require in-game verification by the overlay implementation.

## Closing monologue manicure gesture

> Superseded by the horizontal arm + brush revision below. The original vertical image is archived as `art-source/tutorial/god-arm-nails-vertical-superseded.png` and must not be used as the production gesture.

### Reference contract

- User requested the **closing** tutorial line to use a hand in the spirit of the 💅 emoji. This is a separate asset; the opening finger-heart and pointing sprites remain available.
- Re-inspected `target-arm-open.png`, `target-arm-grip.png`, `god-arm-point.png` and `god-arm-heart.png` before generation.
- Keep the established warm pale skin, long ivory robe sleeve, sparse gray/beige folds, dark pixel outline and coarse low-resolution pixel clusters.
- One hand only: back of hand toward the viewer, four fingers held together and gently curled to display their nails, thumb relaxed at the side. Restrained plum/magenta nail polish is the only new color accent.
- Long sleeve enters continuously from the bottom canvas edge. No second hand, brush, bottle, literal emoji, text, heart or glow.
- Production destination: `assets/image/tutorial/god-arm-nails.png`, original generated transparent PNG without editing.

### Generation prompt

Use case: stylized-concept. Asset type: transparent pixel-art game character hand sprite for the final tutorial monologue. The four reference images show the SAME God's hand and long white robe sleeve; they are identity, costume, warm pale skin palette and pixel-cluster style references. Generate a NEW relaxed confident manicure-display pose inspired by the main manicured hand in the nail-polish emoji. ONE SINGLE HAND ONLY, five fingers total. Back of the hand faces the viewer in a clear three-quarter view, wrist relaxed with a gentle sideways bend; the four fingers are close together, gently curved rather than fully straight, so their short rounded nails are clearly visible. Thumb naturally bends at the side. Give the visible fingernails restrained muted plum/magenta nail polish with only one tiny pixel highlight; no jewelry. Preserve the warm pale skin, very long loose ivory white robe sleeve, charcoal/dark-brown outline and sparse blocky beige-gray sleeve folds of the references. The hand is at the TOP and the long sleeve rises from BELOW. Vertical 2:3 transparent canvas, visible hand centered near (0.50, 0.25). The sleeve continues all the way THROUGH THE BOTTOM EDGE, cropped at the bottom rather than ending in a floating stump. Leave transparent side margins and top margin, no cropped fingertips. Use coarse low-native-resolution pixel clusters equivalent to about 96 by 144 source pixels, hard stepped edges, simple dark outline and flat 2–3 shading tones. No antialiasing, smooth gradients or painterly detail. True transparent RGBA background with no surrounding shadow or glow. No second hand, nail brush, bottle, props, heart, literal emoji symbol, text, arrows, bubbles, sparkles, head or body. Do not copy the finger-heart or pointing poses from the references.

### Visual QA

- Generated with the built-in image tool and reopened locally using `view_image`.
- Confirmed a single connected hand with five visible plum-painted nails, back of hand facing the viewer, relaxed close-set fingers and a naturally offset thumb. The hand presents the manicure, with no brush or second hand.
- Costume and palette retain the existing warm pale skin, ivory long sleeve, sparse gray/beige pixel folds and dark stepped outline. The sleeve extends through the bottom canvas edge.
- Production PNG: **1024 × 1536**, 32-bit RGBA, copied byte-for-byte from the generated output. No image editing or resampling applied.
- Sampled corners and surrounding halo-looking RGB pixels have alpha **0**. Normal RGBA blending must ignore those hidden RGB values.
- Visible bounds at alpha > 127: **(295,127) to (964,1535)** inclusive, approximately **(0.288,0.083) to (0.941,1.000)** normalized.
- Manicure/nail focal area approximately **(0.435,0.166)**; full hand center approximately **(0.48,0.26)**. Wrist enters the top of the sleeve at approximately **(0.57,0.44)**; sleeve opening occupies roughly y **0.41–0.61**.
- Recommended initial display size: **160 × 240 design pixels**, preserving 2:3 ratio, with bottom of sleeve placed below the game-screen edge. Keep the wrist and sleeve opening together and animate the complete sprite from below.
- Source retained at `C:/Users/qinmy/.codex/generated_images/01a14f38-1f7b-7712-ac85-ee1e57b5b626/exec-f91a701a-aadf-4970-a10c-2fd635c5824f.png`.
- This asset is intended for the final tutorial step only. The opening finger-heart remains a separate asset. Full-screen layout and motion require in-game verification.

## Closing manicure correction: horizontal arm with brush

### Reference contract

- Latest explicit user correction: the manicure arm must be horizontal and include the small nail-polish brush like 💅. This supersedes the previous vertical framing and no-brush restriction.
- Re-inspected the previous manicure sprite, pointing arm, and both original white-sleeve references before generation.
- Keep the same hand identity, warm pale skin, coarse dark pixel outline, ivory sleeve, beige-gray folds, restrained purple/magenta nail polish.
- Wide 2:1 canvas. Main hand and nails at left, long sleeve continuous from the right edge, arm/wrist horizontal.
- Add a small visible dark brush cap, short slender stem and pink-purple brush tip angled onto one fingernail. No bottle or large second arm.
- Preserve prior image as `god-arm-nails-vertical-superseded.png`; replace production `assets/image/tutorial/god-arm-nails.png` only after output inspection.

### Generation prompt

Use case: stylized-concept. Asset type: transparent pixel-art game tutorial closing manicure gesture. Reference 1 is the previous manicure hand for skin identity and muted plum/magenta painted nails; reference 2 is the horizontal white-sleeved pointing arm for the required right-to-left arm orientation and costume; references 3 and 4 are the original small pixel-art hand/sleeve style references. Generate the same God's arm in a NEW HORIZONTAL manicure pose with a small nail-polish brush like the nail-polish emoji. WIDE HORIZONTAL 2:1 CANVAS. The long loose ivory white robe sleeve enters THROUGH THE RIGHT EDGE and the forearm/wrist runs almost straight horizontally toward the LEFT. The main hand occupies the left half, with the BACK of the hand and painted fingernails visible to the viewer; the four fingers point loosely left, gently bent and close together, thumb naturally offset below. Five fingers total; no pointing-index gesture. Keep warm pale skin, charcoal/dark-brown stepped outline, simple sparse beige-gray sleeve folds and flat 2–3 shade groups. Add ONE small clearly readable nail-polish brush above the fingers: a compact black/dark cap, short thin stem, and pink-purple brush bristles touching one visible fingernail at a diagonal. The brush is small relative to the hand, around one quarter the hand length; it can appear as a tiny separate brush sprite, no second hand needed. No nail-polish bottle. Keep all fingertips and the full small brush inside the frame with transparent margin. Sleeve must continue through the right canvas edge without a closed cut-off end. Match coarse low-native-resolution pixel clusters equivalent to a 160 by 80 pixel game sprite: hard stepped edges, dark approximately one-source-pixel outline, no antialiasing, soft gradients or painterly texture. True transparent RGBA background. No vertical forearm, second arm, bottle, text, arrow, bubble, literal emoji, heart, sparkles, glow or background shadow.

### Visual QA

- Generated with the built-in image tool, then reopened locally with `view_image` before replacing the production PNG.
- Confirmed the corrected horizontal arm: main hand and painted nails on the left, long white sleeve entering from the right, wrist/forearm almost horizontal. Five visible painted fingernails; no separate pointing-index pose.
- The small dark brush cap, slender stem and pink-purple brush tip are readable above the hand; bristles touch a fingernail diagonally. No bottle, second hand, extra arm or literal emoji.
- Production PNG: **1774 × 887** (2:1), 32-bit RGBA, corner alpha **0**. The generated file was copied byte-for-byte; no image editing, rotation, cropping or resampling.
- Visible bounds at alpha >127: **(161,123) to (1773,833)** inclusive, normalized approximately **(0.091,0.139) to (1.000,0.940)**.
- The sleeve genuinely crosses the right canvas edge: **456** pixels on the rightmost column have alpha >127. Place that edge at or beyond the right game-screen boundary to avoid exposing a cut-off arm.
- Main hand center approximately **(0.34,0.56)**; brush-to-nail contact focal point approximately **(0.15,0.42)**; wrist/sleeve junction approximately **(0.534,0.58)**.
- Recommended starting display size **160 × 80 design pixels**, or a larger 2:1 equivalent as needed for the final tutorial pose. Use its horizontal orientation directly.
- Source retained at `C:/Users/qinmy/.codex/generated_images/01a14f38-1f7b-7712-ac85-ee1e57b5b626/exec-47505e5b-d38f-4256-97b6-c39478dbdf28.png`.
- The earlier vertical no-brush image remains archived for provenance; this horizontal brush image is the active `god-arm-nails.png`.
