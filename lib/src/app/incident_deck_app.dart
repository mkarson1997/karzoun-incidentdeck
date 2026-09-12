import 'package:flutter/material.dart';
import 'package:incidentdeck/src/application/incident_service.dart';
import 'package:incidentdeck/src/data/incident_repository.dart';
import 'package:incidentdeck/src/domain/incident.dart';

class IncidentDeckApp extends StatelessWidget {
  const IncidentDeckApp({super.key, this.service});

  final IncidentService? service;

  @override
  Widget build(BuildContext context) {
    final incidentService = service ??
        IncidentService(repository: InMemoryIncidentRepository());
    return MaterialApp(
      title: 'IncidentDeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: IncidentHomePage(service: incidentService),
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
    final next = switch (incident.status) {
      IncidentStatus.declared => IncidentStatus.acknowledged,
      IncidentStatus.acknowledged => IncidentStatus.mitigated,
      IncidentStatus.mitigated => IncidentStatus.resolved,
      IncidentStatus.resolved => null,
    };
    if (next == null) {
      return;
    }
    await widget.service.transition(incident.id, next);
    if (!mounted) {
      return;
    }
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IncidentDeck'),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Text('LOCAL MODE')),
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
            return Center(child: Text('Unable to load incidents: ${snapshot.error}'));
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
              return Card(
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
                              style: Theme.of(context).textTheme.titleMedium,
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
                        '${incident.timeline.length} timeline events',
                      ),
                      if (incident.status != IncidentStatus.resolved) ...<Widget>[
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: () => _advance(incident),
                          child: Text(_nextActionLabel(incident.status)),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _declareIncident,
        icon: const Icon(Icons.add_alert),
        label: const Text('Declare incident'),
      ),
    );
  }

  String _nextActionLabel(IncidentStatus status) => switch (status) {
        IncidentStatus.declared => 'Acknowledge',
        IncidentStatus.acknowledged => 'Mark mitigated',
        IncidentStatus.mitigated => 'Resolve',
        IncidentStatus.resolved => 'Resolved',
      };
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
              value: _severity,
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
