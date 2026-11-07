package com.stillmusic.player;

import java.util.TreeMap;
import org.junit.runners.model.InitializationError;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.internal.dependency.DependencyResolver;
import org.robolectric.pluginapi.Sdk;
import org.robolectric.pluginapi.SdkProvider;
import org.robolectric.plugins.DefaultSdkProvider;

/** Headless audio tests use only the app's minimum API, with no app resources.
 * Restrict the SDK provider as well as @Config so Robolectric does not download
 * its newest SDK solely to load unused compile-time UI resources.
 * Do not use this runner for application resource/UI tests.
 */
public final class AudioHostTestRunner extends RobolectricTestRunner {
    public AudioHostTestRunner(Class<?> testClass) throws InitializationError {
        super(testClass, defaultInjector().bind(SdkProvider.class, AudioSdkProvider.class).build());
    }

    public static final class AudioSdkProvider extends DefaultSdkProvider {
        public AudioSdkProvider(DependencyResolver resolver) { super(resolver); }

        @Override protected void populateSdks(TreeMap<Integer, Sdk> sdks) {
            super.populateSdks(sdks);
            sdks.keySet().removeIf(api -> api != 28);
        }
    }
}
