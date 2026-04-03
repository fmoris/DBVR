# Joint Selection Guide — Performance Optimization

Only sample the joints you actually need. BabylonJS `trackedMeshes` has 25 entries per hand — reading all is wasteful.

## Joints to Sample Per Gesture

| Gesture | Required Joints (names) | Count |
|---|---|---|
| Pinch | thumb-tip, index-finger-tip | 2 |
| Fist | index-finger-phalanx-proximal, index-finger-tip, middle-finger-tip, ring-finger-tip, pinky-finger-tip | 5 |
| Open Palm | index-finger-tip, middle-finger-tip, ring-finger-tip, pinky-finger-tip, wrist | 5 |
| Point | index-finger-phalanx-proximal, index-finger-tip, middle-finger-tip, ring-finger-tip | 4 |
| Peace | index-finger-tip, middle-finger-tip, ring-finger-tip, pinky-finger-tip | 4 |
| Thumbs Up | thumb-tip, wrist, index-finger-tip, middle-finger-tip | 4 |
| Wave | wrist + open palm joints | 6 |
| Spread | index-finger-tip, pinky-finger-tip + all 4 finger bend checks | 8 |
| OK | thumb-tip, index-finger-tip, middle-finger-tip, ring-finger-tip, pinky-finger-tip | 5 |
| Two-hand scale | thumb-tip + index-tip (both hands) | 4 total |

## Index Map (WebXR spec)

```
0  = wrist
1  = thumb-metacarpal
2  = thumb-phalanx-proximal
3  = thumb-phalanx-distal
4  = thumb-tip
5  = index-finger-metacarpal
6  = index-finger-phalanx-proximal
7  = index-finger-phalanx-intermediate
8  = index-finger-phalanx-distal
9  = index-finger-tip
10 = middle-finger-metacarpal
11 = middle-finger-phalanx-proximal
12 = middle-finger-phalanx-intermediate
13 = middle-finger-phalanx-distal
14 = middle-finger-tip
15 = ring-finger-metacarpal
16 = ring-finger-phalanx-proximal
17 = ring-finger-phalanx-intermediate
18 = ring-finger-phalanx-distal
19 = ring-finger-tip
20 = pinky-finger-metacarpal
21 = pinky-finger-phalanx-proximal
22 = pinky-finger-phalanx-intermediate
23 = pinky-finger-phalanx-distal
24 = pinky-finger-tip
```

## Pre-cache Joint References

Cache joint meshes on hand-added, don't look them up every frame:

```typescript
interface CachedHand {
  thumbTip:    AbstractMesh;
  indexTip:    AbstractMesh;
  middleTip:   AbstractMesh;
  ringTip:     AbstractMesh;
  pinkyTip:    AbstractMesh;
  indexProx:   AbstractMesh;
  middleProx:  AbstractMesh;
  wrist:       AbstractMesh;
}

function cacheHand(hand: WebXRHand): CachedHand {
  const m = hand.trackedMeshes!;
  return {
    thumbTip:   m[4],
    indexTip:   m[9],
    middleTip:  m[14],
    ringTip:    m[19],
    pinkyTip:   m[24],
    indexProx:  m[6],
    middleProx: m[11],
    wrist:      m[0],
  };
}
```

## Sampling Rate Recommendation

| Gesture Type | Recommended Hz | Notes |
|---|---|---|
| Static poses (fist, pinch) | 30Hz | Debounce 3–4 frames |
| Combo sequences | 30Hz | Timeout window 1.5–2s |
| Wave / motion gestures | 30Hz | Need history buffer ~20 frames |
| Pinch strength (analog) | 60Hz | Smooth input for sliders/scaling |
| Grab physics | 60Hz | Needs tight coupling to physics step |