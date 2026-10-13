package io.openim.flutter_openim_sdk.connectivity;


import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;

import io.flutter.Log;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import open_im_sdk.Open_im_sdk;


public class ConnectivityListener implements open_im_sdk_callback.Base {
    public static final String CONNECTIVITY_ACTION = "android.net.conn.CONNECTIVITY_CHANGE";
    private Context context;
    private ConnectivityManager connectivityManager;
    private Connectivity connectivity;
    private ConnectivityBroadcastReceiver receiver;
    private ConnectivityManager.NetworkCallback networkCallback;
    private Network validatedNetwork;
    private boolean receivedInitialNetwork;

    public ConnectivityListener(Context context) {
        this.context = context;
        this.connectivityManager =
                (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        this.connectivity = new Connectivity(connectivityManager);
        this.receiver = new ConnectivityBroadcastReceiver(this);
    }

    private void onChangedNetworkStatus() {
        String status = connectivity.getNetworkType();
        if (!"none".equals(status)) {
            Log.i("ConnectivityListener", "networkStatusChanged: " + status);
            if (io.openim.flutter_openim_sdk.runtime.NativeIMRuntime.get().isInitialized()) {
                Open_im_sdk.networkStatusChanged(this, String.valueOf(System.currentTimeMillis()));
            }
        }
    }

    public void register() {
        if (networkCallback != null) return;
        if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network network) {
                    Log.i("ConnectivityListener", "network available; waiting for validation");
                }

                @Override
                public synchronized void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) {
                    if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) return;
                    if (network.equals(validatedNetwork)) return;
                    boolean changed = receivedInitialNetwork;
                    receivedInitialNetwork = true;
                    validatedNetwork = network;
                    // Initial registration is a snapshot, not a network switch.
                    if (changed) onChangedNetworkStatus();
                }

                @Override
                public synchronized void onLost(Network network) {
                    if (network.equals(validatedNetwork)) validatedNetwork = null;
                    Log.i("ConnectivityListener", "network lost");
                }
            };
            connectivity.getConnectivityManager().registerDefaultNetworkCallback(networkCallback);
        } else {
            context.registerReceiver(receiver, new IntentFilter(CONNECTIVITY_ACTION));
        }
    }

    public void unregisterReceiver() {
        if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            if (networkCallback != null) {
                connectivity.getConnectivityManager().unregisterNetworkCallback(networkCallback);
                networkCallback = null;
                validatedNetwork = null;
                receivedInitialNetwork = false;
            }
        } else {
            try {
                context.unregisterReceiver(receiver);
                receiver = null;
            } catch (Exception e) {
                //listen never called, ignore the error
            }
        }
    }

    @Override
    public void onError(int i, String s) {

    }

    @Override
    public void onSuccess(String s) {

    }

    public static class ConnectivityBroadcastReceiver extends BroadcastReceiver {
        ConnectivityListener listener;

        public ConnectivityBroadcastReceiver(ConnectivityListener listener) {
            this.listener = listener;
        }

        @Override
        public void onReceive(Context context, Intent intent) {
            if (null != listener && CONNECTIVITY_ACTION.equals(intent.getAction())) {
                listener.onChangedNetworkStatus();
            }
        }
    }
}
