import 'package:flutter/material.dart';

abstract final class AppShapes {
  static const radiusSmall = 10.0;
  static const radiusMedium = 14.0;
  static const radiusLarge = 20.0;
  static const radiusExtraLarge = 28.0;

  static const smallRadius = BorderRadius.all(Radius.circular(radiusSmall));
  static const mediumRadius = BorderRadius.all(Radius.circular(radiusMedium));
  static const largeRadius = BorderRadius.all(Radius.circular(radiusLarge));
  static const extraLargeRadius = BorderRadius.all(
    Radius.circular(radiusExtraLarge),
  );

  static RoundedRectangleBorder card({Color? borderColor}) {
    return RoundedRectangleBorder(
      borderRadius: largeRadius,
      side:
          borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor),
    );
  }
}
