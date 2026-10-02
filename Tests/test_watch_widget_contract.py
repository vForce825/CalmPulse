"""Static source acceptance contracts; these are not Apple runtime or simulator evidence."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class WatchWidgetContracts(unittest.TestCase):
    def source(self,path):
        file=ROOT/path
        return file.read_text() if file.exists() else ''
    def test_shared_provider_reads_only_protected_summary_and_schedules_transition(self):
        source=self.source('Apps/WidgetShared/PulseTimelineProvider.swift')
        for contract in ['WidgetCacheFile.groupID','summary.json','WidgetCacheFile.read','nextTransition','Timeline(entries:', 'protectedDataAvailable: false']:
            self.assertIn(contract,source)
        self.assertNotIn('import HealthKit',source)
        self.assertNotIn('reloadAllTimelines',source)
    def test_platforms_declare_supported_families_without_duplicate_provider(self):
        iphone=self.source('Apps/iOSWidgets/CalmPulseWidget.swift')
        watch=self.source('Apps/WatchWidgets/CalmPulseWidget.swift')
        for source in [iphone,watch]:
            for token in ['PulseTimelineProvider()', 'PulseWidgetView', '.accessoryCircular', '.accessoryRectangular', '.accessoryInline']:
                self.assertIn(token,source)
            self.assertNotIn('struct PulseProvider',source)
        for family in ['.systemSmall','.systemMedium']:
            self.assertIn(family,iphone)
            self.assertNotIn(family,watch)
    def test_widget_privacy_age_and_unavailable_contracts(self):
        source=self.source('Apps/WidgetShared/PulseWidgetView.swift')
        for token in ['.privacySensitive()', 'observedAt', 'style: .timer','历史读数','已隐藏数值','accessibilityLabel','widgetRenderingMode']:
            self.assertIn(token,source)
        self.assertNotIn('压力百分比',source)
    def test_watch_flows_are_local_and_lifecycle_aware(self):
        source=self.source('Apps/Watch/CalmPulseApp.swift')
        for token in ['AppRuntime()', 'runtime.start()', 'runtime.foreground()', 'scenePhase', 'model.request([.sdnn, .restingHeartRate])', 'TrendsView(model: model)', 'BreathingView(model: model)', 'HealthOverviewView(model: model)', 'model.saveHabit','baselineDayCount','baselineSampleCount','未排除运动影响','watch.readCore','watch.quickLog']:
            self.assertIn(token,source)
        for token in ['HKWorkoutSession','startWorkout','requestAuthorization']:
            self.assertNotIn(token,source)
    def test_watch_notifications_require_explicit_local_opt_in(self):
        source=self.source('Apps/Watch/CalmPulseApp.swift')
        self.assertIn('if model.settings.notifications.enabled && model.settings.notifications.owner == .watch',source)
        section=source.split('Section("本机通知")',1)[-1].split('Section("同步与隐私")',1)[0]
        for token in ['允许本机通知','watch.notifications.request','SystemNotificationClient().requestPermission()','本机通知已允许','本机通知未允许']:
            self.assertIn(token,section)
        self.assertNotIn('changeSettings',section)
        self.assertNotIn('.task',section)
if __name__=='__main__':unittest.main()
