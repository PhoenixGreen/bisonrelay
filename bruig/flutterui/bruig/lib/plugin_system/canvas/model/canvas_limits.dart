// canvas_limits.dart is the sizes and counts a canvas is held to, as it is
// made here and as a received one is read: how long a scene may run, how
// many scenes, elements and guides there may be. The limits on a single field (a
// string's length, a list's count) are with the readers, in json_read.dart.

/// defaultFrameRate is the rate a canvas for a screen runs at.
const int defaultFrameRate = 24;

/// defaultFrameCount is one frame: a still.
const int defaultFrameCount = 1;

/// maxFrameCount is the longest one scene may be: twenty minutes at
/// [audioFrameRate], a hundred at 24 a second.
const int maxFrameCount = 144000;

/// maxSceneElements and maxScenes are the most of each a canvas is read
/// with: far more than any canvas made here, and a received one's million
/// shapes would be drawn every frame.
const int maxSceneElements = 10000, maxScenes = 1000;

/// maxGuides is the most guide lines a canvas is read with: more than
/// anyone puts down by hand, and few enough that drawing every one on each
/// repaint and snapping to them on each step of a drag stays cheap.
const int maxGuides = 1000;

/// audioFrameRate is the steps a second a piece of sound's timeline counts
/// in: fine enough that any beat lands within a few milliseconds of a step.
const int audioFrameRate = 120;

/// maxSequenceFrames is the longest a whole document may run, every scene
/// end to end. It must stay well above [maxFrameCount], or a run of long
/// scenes is cut short.
const int maxSequenceFrames = maxFrameCount * 100;
