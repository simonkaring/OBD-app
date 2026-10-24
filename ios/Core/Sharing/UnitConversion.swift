/// Conversion factors shared by the app's `UnitPreferences` and the app-group snapshot.
///
/// Lives in `Core/Sharing` — the only directory besides `Widgets/` that compiles into
/// the widget extension — so the app and the widget cannot drift apart on rounding.
public enum UnitConversion {
    public static let kilometersPerMile = 1.609_344
    public static let kilowattsPerHorsepower = 0.745_699_872
}
