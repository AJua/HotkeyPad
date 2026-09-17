import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'safe_insets.dart';
import 'unsupported_page.dart';

/// One entry in the discovery list, kept across advertisements so the list
/// does not flicker as a device re-advertises.
class DiscoveredDevice {
  DiscoveredDevice({
    required this.peripheral,
    required this.rssi,
    required this.name,
    required this.isHost,
    required this.lastSeen,
  });

  final Peripheral peripheral;
  final int rssi;
  final String? name;
  final bool isHost;
  final DateTime lastSeen;

  String get id => peripheral.uuid.toString();
}

/// A diagnostic: what this radio can see, and which of it speaks HotkeyPad.
/// Connecting happens automatically on the deck; this is for working out why
/// it did not.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  CentralManager? _central;
  Object? _initError;

  final _devices = <String, DiscoveredDevice>{};
  final _subscriptions = <StreamSubscription>[];
  Timer? _ticker;

  BluetoothLowEnergyState _state = BluetoothLowEnergyState.unknown;
  bool _discovering = false;
  bool _hostsOnly = false;

  @override
  void initState() {
    super.initState();
    _setUp();
    // Android reports `unauthorized` until the runtime permissions are
    // granted, so ask on entry. Waiting for a button press cannot work: the
    // button would be gated on the very state the permission unlocks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_central != null && _state != BluetoothLowEnergyState.poweredOn) {
        _ensureAuthorized();
      }
    });
  }

  /// Returns whether the app may use Bluetooth. Only Android has a runtime
  /// permission to ask for; elsewhere authorization is implied.
  Future<bool> _ensureAuthorized() async {
    final central = _central;
    if (central == null) return false;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await central.authorize();
    } catch (error) {
      _showMessage('$error');
      return false;
    }
  }

  void _setUp() {
    try {
      final central = CentralManager();
      _central = central;
      _state = central.state;
      _subscriptions.add(
        central.stateChanged.listen((event) {
          if (!mounted) return;
          setState(() => _state = event.state);
          // Losing the adapter silently stops the scan on every platform.
          if (event.state != BluetoothLowEnergyState.poweredOn) {
            setState(() => _discovering = false);
          }
        }),
      );
      _subscriptions.add(central.discovered.listen(_onDiscovered));
    } catch (error) {
      // CentralManager() throws when no platform implementation is
      // registered, which is what happens on the web.
      _initError = error;
    }
  }

  void _onDiscovered(DiscoveredEventArgs event) {
    if (!mounted) return;
    final advertisement = event.advertisement;
    setState(() {
      _devices[event.peripheral.uuid.toString()] = DiscoveredDevice(
        peripheral: event.peripheral,
        rssi: event.rssi,
        name: _advertisedName(advertisement),
        isHost: advertisement.serviceUUIDs.contains(HotkeyPad.serviceUuid),
        lastSeen: DateTime.now(),
      );
    });
  }

  /// [Advertisement.name] throws [UnsupportedError] on Linux and Windows.
  String? _advertisedName(Advertisement advertisement) {
    try {
      return advertisement.name;
    } on UnsupportedError {
      return null;
    }
  }

  Future<void> _toggleDiscovery() async {
    final central = _central;
    if (central == null) return;
    // Captured before any `await` below — the lints correctly flag reading
    // an inherited widget's context after a gap, since this State may no
    // longer be mounted (or in the same tree position) by the time it
    // resumes; _showMessage's own `mounted` check guards the SnackBar call
    // itself, but not this lookup.
    final l10n = AppLocalizations.of(context)!;
    try {
      if (_discovering) {
        await central.stopDiscovery();
        _ticker?.cancel();
        _ticker = null;
        if (mounted) setState(() => _discovering = false);
        return;
      }

      if (_state == BluetoothLowEnergyState.poweredOff) {
        _showMessage(l10n.turnBluetoothOnFirst);
        return;
      }
      if (!await _ensureAuthorized()) {
        _showMessage(l10n.bluetoothPermissionDeniedSnackbar);
        return;
      }

      // Deliberately not gated on the cached state: it is only refreshed when
      // the app resumes, so right after granting it still reads unauthorized.
      await central.startDiscovery();
      if (!mounted) return;
      setState(() => _discovering = true);
      // Only drives the "last seen" labels; discovery itself is push-based.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (error) {
      _showMessage('$error');
      if (mounted) setState(() => _discovering = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    // Fire-and-forget, error swallowed: a device with no BLE radio throws
    // the same platform-channel error from every CentralManager call, this
    // one included — see deck_page.dart's _stopDiscoverySafely for the
    // confirmed crash this same shape caused there.
    if (_discovering) {
      unawaited(_central?.stopDiscovery().catchError((_) {}));
    }
    super.dispose();
  }

  List<DiscoveredDevice> get _visibleDevices {
    final devices =
        _devices.values.where((d) => !_hostsOnly || d.isHost).toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return devices;
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return UnsupportedPage(details: '$_initError');
    }

    final l10n = AppLocalizations.of(context)!;
    final devices = _visibleDevices;
    final hostCount = _devices.values.where((d) => d.isHost).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nearbyDevices),
        actions: [
          IconButton(
            tooltip: l10n.clearDeviceList,
            onPressed:
                _devices.isEmpty ? null : () => setState(_devices.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                FilterChip(
                  selected: _hostsOnly,
                  label: Text(l10n.hotkeypadHostsCount(hostCount)),
                  avatar: const Icon(Icons.dns_outlined, size: 18),
                  onSelected: (value) => setState(() => _hostsOnly = value),
                ),
                const Spacer(),
                Text(
                  l10n.devicesShownCount(devices.length),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _AdapterBanner(state: _state, onGrant: _ensureAuthorized),
          Expanded(
            child:
                devices.isEmpty
                    ? _EmptyState(discovering: _discovering)
                    : ListView.separated(
                      padding: safeScrollPadding(context),
                      itemCount: devices.length,
                      separatorBuilder:
                          (_, _) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) =>
                          _DeviceTile(device: devices[index]),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _state == BluetoothLowEnergyState.unsupported
            ? null
            : _toggleDiscovery,
        backgroundColor: _state == BluetoothLowEnergyState.unsupported
            ? Theme.of(context).disabledColor
            : null,
        icon: Icon(_discovering ? Icons.stop : Icons.bluetooth_searching),
        label: Text(_discovering ? l10n.stopScan : l10n.scanAction),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final age = DateTime.now().difference(device.lastSeen);
    final stale = age.inSeconds >= 10;
    final theme = Theme.of(context);

    return Opacity(
      opacity: stale ? 0.45 : 1,
      child: ListTile(
        leading: _SignalIcon(rssi: device.rssi),
        title: Row(
          children: [
            Flexible(
              child: Text(
                device.name?.isNotEmpty == true
                    ? device.name!
                    : l10n.unknownDevice,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight:
                      device.name == null ? FontWeight.normal : FontWeight.w600,
                  fontStyle:
                      device.name == null ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (device.isHost) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.hostBadge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          l10n.deviceSubtitle(device.id, device.rssi, age.inSeconds),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _SignalIcon extends StatelessWidget {
  const _SignalIcon({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    // Rough buckets: -60 and up is across the desk, -90 is another room.
    final (IconData icon, Color color) = switch (rssi) {
      >= -60 => (Icons.signal_cellular_alt, Colors.green),
      >= -75 => (Icons.signal_cellular_alt_2_bar, Colors.orange),
      _ => (Icons.signal_cellular_alt_1_bar, Colors.red),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color),
    );
  }
}

class _AdapterBanner extends StatelessWidget {
  const _AdapterBanner({required this.state, required this.onGrant});

  final BluetoothLowEnergyState state;
  final Future<bool> Function() onGrant;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = switch (state) {
      BluetoothLowEnergyState.poweredOn => null,
      BluetoothLowEnergyState.poweredOff => l10n.bluetoothOff,
      BluetoothLowEnergyState.unauthorized => l10n.bluetoothUnauthorized,
      BluetoothLowEnergyState.unsupported => l10n.bluetoothUnsupported,
      BluetoothLowEnergyState.unknown => l10n.bluetoothCheckingAdapter,
    };
    if (message == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: safeScrollPadding(
          context,
          horizontal: 16,
        ).copyWith(top: 10, bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.bluetooth_disabled, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
            if (state == BluetoothLowEnergyState.unauthorized)
              TextButton(
                onPressed: () => onGrant(),
                child: Text(l10n.grantAction),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.discovering});

  final bool discovering;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            discovering ? Icons.radar : Icons.bluetooth_searching,
            size: 56,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 12),
          Text(
            discovering
                ? l10n.scanningForDevices
                : l10n.tapScanToLookForDevices,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
