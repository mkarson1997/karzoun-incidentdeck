import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:incidentdeck/src/app/default_incident_service.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/domain/incident.dart';

typedef IncidentServiceFactory = Future<IncidentService> Function();

class IncidentDeckApp extends StatefulWidget {
  const IncidentDeckApp({super.key, this.service, this.serviceFactory});

  final IncidentService? service;
  final IncidentServiceFactory? serviceFactory;

  @override
  State<IncidentDeckApp> createState() => _IncidentDeckAppState();
}

class _IncidentDeckAppState extends State<IncidentDeckApp> {
  late Future<IncidentService> _service;

  @override
  void initState() {
    super.initState();
    _service = _resolveService();
  }

  @override
  void didUpdateWidget(IncidentDeckApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.service != oldWidget.service ||
        widget.serviceFactory != oldWidget.serviceFactory) {
      _service = _resolveService();
    }
  }

  Future<IncidentService> _resolveService() {
    final service = widget.service;
    if (service != null) {
      return Future<IncidentService>.value(service);
    }
    final factory = widget.serviceFactory ?? createDefaultIncidentService;
    return factory();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IncidentDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: FutureBuilder<IncidentService>(
        future: _service,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to open local incident storage: ${snapshot.error}',
                  ),
                ),
              ),
            );
          }
          return IncidentHomePage(service: snapshot.requireData);
        },
      ),
    );
  }
}

class IncidentHomePage extends StatefulWidget {
  const IncidentHomePage({required this.service, super.key});

  final IncidentService service;

  @override
  State<IncidentHomePage> createState() => _IncidentHomePageState();
}

class _IncidentHomePageState extends State<IncidentHomePage> {
  late Future<List<Incident>> _incidents;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(IncidentHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.service != oldWidget.service) {
      _reload();
    }
  }

  void _reload() {
    _incidents = widget.service.listIncidents();
  }

  Future<void> _declareIncident() async {
    final draft = await showDialog<_IncidentDraft>(
      context: context,
      builder: (context) => const _DeclareIncidentDialog(),
    );
    if (draft == null) {
      return;
    }
    await widget.service.declareIncident(
      title: draft.title,
      summary: draft.summary,
      severity: draft.severity,
    );
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  Future<void> _advance(Incident incident) async {
    final next = _nextStatus(incident.status);
    if (next == null) {
      return;
    }
    await widget.service.transition(incident.id, next);
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  Future<void> _openIncident(Incident incident) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => IncidentDetailPage(
          service: widget.service,
          incidentId: incident.id,
        ),
      ),
    );
    if (mounted) {
      setState(_reload);
    }
  }

  Future<void> _exportSnapshot() async {
    final snapshot = await widget.service.exportSnapshot();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export local snapshot'),
        content: SizedBox(
          width: 640,
          height: 420,
          child: SingleChildScrollView(child: SelectableText(snapshot)),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: snapshot));
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> _importSnapshot() async {
    var draft = '';
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import local snapshot'),
        content: SizedBox(
          width: 640,
          child: TextField(
            minLines: 10,
            maxLines: 16,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'IncidentDeck JSON snapshot',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Validate and replace'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) {
      return;
    }

    try {
      await widget.service.importSnapshot(raw);
      if (!mounted) {
        return;
      }
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snapshot imported successfully.')),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import rejected: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          _declareIncident,
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
          _declareIncident,
      const SingleActivator(LogicalKeyboardKey.keyE, control: true):
          _exportSnapshot,
      const SingleActivator(LogicalKeyboardKey.keyE, meta: true):
          _exportSnapshot,
      const SingleActivator(LogicalKeyboardKey.keyI, control: true):
          _importSnapshot,
      const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
          _importSnapshot,
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('IncidentDeck'),
            actions: <Widget>[
              Tooltip(
                message: 'Import snapshot (Ctrl/⌘+I)',
                child: IconButton(
                  onPressed: _importSnapshot,
                  icon: const Icon(
                    Icons.file_download_outlined,
                    semanticLabel: 'Import snapshot',
                  ),
                ),
              ),
              Tooltip(
                message: 'Export snapshot (Ctrl/⌘+E)',
                child: IconButton(
                  onPressed: _exportSnapshot,
                  icon: const Icon(
                    Icons.file_upload_outlined,
                    semanticLabel: 'Export snapshot',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(kIsWeb ? 'WEB EPHEMERAL' : 'LOCAL DURABLE'),
                ),
              ),
            ],
          ),
          body: FutureBuilder<List<Incident>>(
            future: _incidents,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Unable to load incidents: ${snapshot.error}'),
                );
              }
              final incidents = snapshot.data ?? const <Incident>[];
              if (incidents.isEmpty) {
                return const _EmptyState();
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: incidents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final incident = incidents[index];
                  return Semantics(
                    container: true,
                    button: true,
                    label:
                        '${incident.title}, ${incident.severity.name}, '
                        '${incident.status.name}',
                    child: Card(
                      child: InkWell(
                        onTap: () => _openIncident(incident),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  _SeverityBadge(severity: incident.severity),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      incident.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  Text(incident.status.name.toUpperCase()),
                                ],
                              ),
                              if (incident.summary.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(incident.summary),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                'Revision ${incident.revision} · '
                                '${incident.responders.length} responders · '
                                '${incident.alerts.length} alerts · '
                                '${incident.timeline.length} timeline events',
                              ),
                              if (incident.status !=
                                  IncidentStatus.resolved) ...<Widget>[
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: () => _advance(incident),
                                  child: Text(
                                    _nextActionLabel(incident.status),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          floatingActionButton: Semantics(
            button: true,
            label: 'Declare incident',
            child: FloatingActionButton.extended(
              onPressed: _declareIncident,
              tooltip: 'Declare incident (Ctrl/⌘+N)',
              icon: const Icon(Icons.add_alert),
              label: const Text('Declare incident'),
            ),
          ),
        ),
      ),
    );
  }
}

class IncidentDetailPage extends StatefulWidget {
  const IncidentDetailPage({
    required this.service,
    required this.incidentId,
    super.key,
  });

  final IncidentService service;
  final String incidentId;

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  late Future<Incident?> _incident;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _incident = widget.service.getIncident(widget.incidentId);
  }

  Future<void> _mutate(Future<Incident> Function() mutation) async {
    try {
      await mutation();
      if (mounted) {
        setState(_reload);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Operation failed: $error')));
      }
    }
  }

  Future<String?> _prompt(String title, String label) async {
    var draft = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onChanged: (value) => draft = value,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> _assignResponder() async {
    final responder = await _prompt('Assign responder', 'Responder id');
    if (responder != null) {
      await _mutate(
        () => widget.service.assignResponder(widget.incidentId, responder),
      );
    }
  }

  Future<void> _addNote() async {
    final note = await _prompt('Add timeline note', 'Note');
    if (note != null) {
      await _mutate(() => widget.service.addNote(widget.incidentId, note));
    }
  }

  Future<void> _raiseAlert() async {
    final message = await _prompt('Raise local alert', 'Alert message');
    if (message != null) {
      await _mutate(
        () => widget.service.raiseAlert(widget.incidentId, message),
      );
    }
  }

  Future<void> _advance(Incident incident) async {
    final next = _nextStatus(incident.status);
    if (next != null) {
      await _mutate(() => widget.service.transition(incident.id, next));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incident detail')),
      body: FutureBuilder<Incident?>(
        future: _incident,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final incident = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load incident: ${snapshot.error}'),
            );
          }
          if (incident == null) {
            return const Center(child: Text('Incident no longer exists.'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  incident.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _SeverityBadge(severity: incident.severity),
                  const SizedBox(width: 12),
                  Text(incident.status.name.toUpperCase()),
                  const Spacer(),
                  Text('Revision ${incident.revision}'),
                ],
              ),
              if (incident.summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(incident.summary),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _assignResponder,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Assign responder'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addNote,
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Add note'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _raiseAlert,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Raise alert'),
                  ),
                  if (incident.status != IncidentStatus.resolved)
                    FilledButton.icon(
                      onPressed: () => _advance(incident),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_nextActionLabel(incident.status)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionTitle('Responders (${incident.responders.length})'),
              const SizedBox(height: 8),
              if (incident.responders.isEmpty)
                const Text('No responders assigned.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: incident.responders
                      .map((responder) => Chip(label: Text(responder)))
                      .toList(),
                ),
              const SizedBox(height: 24),
              _SectionTitle('Alerts (${incident.alerts.length})'),
              const SizedBox(height: 8),
              if (incident.alerts.isEmpty)
                const Text('No local alerts.')
              else
                ...incident.alerts.reversed.map(
                  (alert) => Card(
                    child: ListTile(
                      leading: Icon(
                        alert.isAcknowledged
                            ? Icons.notifications_none
                            : Icons.notification_important,
                      ),
                      title: Text(alert.message),
                      subtitle: Text(
                        alert.isAcknowledged
                            ? 'Acknowledged'
                            : 'Awaiting acknowledgement',
                      ),
                      trailing: alert.isAcknowledged
                          ? const Icon(Icons.check_circle_outline)
                          : TextButton(
                              onPressed: () => _mutate(
                                () => widget.service.acknowledgeAlert(
                                  incident.id,
                                  alert.id,
                                ),
                              ),
                              child: const Text('Acknowledge'),
                            ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              _SectionTitle('Timeline (${incident.timeline.length})'),
              const SizedBox(height: 8),
              ...incident.timeline.reversed.map(
                (entry) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(entry.message),
                  subtitle: Text('${entry.kind.name} · ${entry.at.toLocal()}'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.health_and_safety_outlined, size: 56),
            SizedBox(height: 16),
            Text('No active incidents'),
            SizedBox(height: 8),
            Text('Declare an incident to start a local response timeline.'),
          ],
        ),
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final IncidentSeverity severity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(severity.name.toUpperCase()),
      ),
    );
  }
}

class _IncidentDraft {
  const _IncidentDraft({
    required this.title,
    required this.summary,
    required this.severity,
  });

  final String title;
  final String summary;
  final IncidentSeverity severity;
}

class _DeclareIncidentDialog extends StatefulWidget {
  const _DeclareIncidentDialog();

  @override
  State<_DeclareIncidentDialog> createState() => _DeclareIncidentDialogState();
}

class _DeclareIncidentDialogState extends State<_DeclareIncidentDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _summary = TextEditingController();
  IncidentSeverity _severity = IncidentSeverity.sev2;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Declare incident'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summary,
              decoration: const InputDecoration(labelText: 'Summary'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IncidentSeverity>(
              initialValue: _severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: IncidentSeverity.values
                  .map(
                    (severity) => DropdownMenuItem<IncidentSeverity>(
                      value: severity,
                      child: Text(severity.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (severity) {
                if (severity != null) {
                  setState(() => _severity = severity);
                }
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              return;
            }
            Navigator.pop(
              context,
              _IncidentDraft(
                title: _title.text,
                summary: _summary.text,
                severity: _severity,
              ),
            );
          },
          child: const Text('Declare'),
        ),
      ],
    );
  }
}

IncidentStatus? _nextStatus(IncidentStatus status) => switch (status) {
  IncidentStatus.declared => IncidentStatus.acknowledged,
  IncidentStatus.acknowledged => IncidentStatus.mitigated,
  IncidentStatus.mitigated => IncidentStatus.resolved,
  IncidentStatus.resolved => null,
};

String _nextActionLabel(IncidentStatus status) => switch (status) {
  IncidentStatus.declared => 'Acknowledge',
  IncidentStatus.acknowledged => 'Mark mitigated',
  IncidentStatus.mitigated => 'Resolve',
  IncidentStatus.resolved => 'Resolved',
};
