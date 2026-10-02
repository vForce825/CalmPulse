"""Source contracts complement (not replace) the Apple simulator UI tests."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class StressFirstContracts(unittest.TestCase):
    def test_phone_primary_surface_is_status_first(self):
        source=(ROOT/'Apps/UI/PhoneViews.swift').read_text().split('private struct HabitDraft')[0]
        self.assertIn('StressHero', source)
        self.assertIn('TodayStressTimeline', source)
        self.assertNotIn('不混入 SDNN 趋势指标', source)
    def test_watch_and_widget_share_presentation(self):
        for path in ['Apps/Watch/CalmPulseApp.swift', 'Apps/WidgetShared/PulseWidgetView.swift']:
            self.assertIn('StressPresentation', (ROOT/path).read_text())
    def test_debug_visual_fixtures_cover_states(self):
        source=(ROOT/'Tests/VisualSupport/StressDemonstration.swift').read_text() if (ROOT/'Tests/VisualSupport/StressDemonstration.swift').exists() else ''
        for state in ['relaxed','steady','tense','high','learning','stale','invalid']:
            self.assertIn('"'+state+'"',source)

    def test_advanced_details_retain_resting_heart_rate(self):
        source=(ROOT/'Apps/UI/StressViews.swift').read_text().split('struct StressDetailsView: View')[1]
        self.assertIn('.restingHeartRate', source)
        self.assertIn('静息心率', source)

    def test_detail_reading_uses_the_same_validity_gate(self):
        source=(ROOT/'Apps/UI/CommonViews.swift').read_text().split('struct ReadingView: View')[1].split('struct HabitEditor')[0]
        self.assertIn('StressPresentation(', source)
        self.assertNotIn('summary.assessment.band?.title', source)
