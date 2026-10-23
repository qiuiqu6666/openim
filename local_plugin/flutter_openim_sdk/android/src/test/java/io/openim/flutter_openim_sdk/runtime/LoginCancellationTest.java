package io.openim.flutter_openim_sdk.runtime;

import org.junit.Test;
import org.mockito.ArgumentCaptor;
import open_im_sdk_callback.Base;
import static org.mockito.Mockito.*;

public class LoginCancellationTest {
    @Test public void cancellationWaitsAndLateErrorCannotClearNewSession() {
        CoreLifecycle core = mock(CoreLifecycle.class);
        when(core.initSDK(any(), anyString(), anyString())).thenReturn(true);
        when(core.getLoginStatus(anyString())).thenReturn(2L);
        NativeIMRuntime runtime = new NativeIMRuntime(core, Runnable::run, ignored -> {});
        runtime.initialize("init", "{}");
        Base first = mock(Base.class);
        runtime.login(first, "old", "account", "credential");
        ArgumentCaptor<Base> old = ArgumentCaptor.forClass(Base.class);
        verify(core).login(old.capture(), eq("old"), anyString(), anyString());
        Base ack = mock(Base.class);
        runtime.cancelLogin(ack, "cancel", "old");
        ArgumentCaptor<Base> cancel = ArgumentCaptor.forClass(Base.class);
        verify(core).cancelLogin(cancel.capture(), eq("cancel"), eq("old"));
        runtime.login(mock(Base.class), "blocked", "account", "credential");
        verify(core, times(1)).login(any(), anyString(), anyString(), anyString());
        verifyNoInteractions(ack);
        cancel.getValue().onSuccess("");
        verify(first).onError(eq(10004), anyString());
        verify(ack).onSuccess("");
        Base next = mock(Base.class);
        runtime.login(next, "new", "account", "credential");
        old.getValue().onError(10004, "late");
        org.junit.Assert.assertEquals("account", runtime.accountID());
        verifyNoInteractions(next);
        verify(core, times(2)).login(any(), anyString(), anyString(), anyString());
        verify(core, times(1)).initSDK(any(), anyString(), anyString());
        verify(core, never()).unInitSDK(anyString());
    }
}
