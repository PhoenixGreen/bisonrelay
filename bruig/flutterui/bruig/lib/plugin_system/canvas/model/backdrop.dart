// backdrop.dart is the choice every background makes first: a flat generated
// pattern, a 3D stage (a floor and a wall seen through a camera, that
// characters stand on), or parallax scenery that slides as the camera pans.
// The stage's own settings are a StageElement the background carries, as it
// carries its picture and its video.

/// BackdropKind is what a background draws.
enum BackdropKind {
  flat("2D background"),
  stage("3D stage"),
  parallax("Parallax");

  final String label;
  const BackdropKind(this.label);

  static BackdropKind fromName(String? name) =>
      values.firstWhere((k) => k.name == name, orElse: () => flat);
}

/// backgroundStageId is the id of the stage the canvas's own background
/// carries: what a character standing on it names as its stage. Characters
/// on a Background element's stage name that element instead.
const String backgroundStageId = "backgroundStage";

/// backgroundParallaxId is the id of the parallax scenery the canvas's own
/// background carries, which its camera's keys are kept under.
const String backgroundParallaxId = "backgroundParallax";
