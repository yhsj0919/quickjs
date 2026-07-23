import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiStarfieldPage extends StatelessWidget {
  const QuickjsUiStarfieldPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Warp Starfield',
    path: 'assets/quickjs_ui/particle_starfield_page.mjs',
  );
}

class QuickjsUiNeonGalaxyPage extends StatelessWidget {
  const QuickjsUiNeonGalaxyPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Neon Galaxy',
    path: 'assets/quickjs_ui/particle_galaxy_page.mjs',
  );
}

class QuickjsUiFirefliesPage extends StatelessWidget {
  const QuickjsUiFirefliesPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Firefly Garden',
    path: 'assets/quickjs_ui/particle_fireflies_page.mjs',
  );
}

class QuickjsUiEnergyBurstPage extends StatelessWidget {
  const QuickjsUiEnergyBurstPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Energy Burst',
    path: 'assets/quickjs_ui/particle_energy_burst_page.mjs',
  );
}

class QuickjsUiArcGaugePage extends StatelessWidget {
  const QuickjsUiArcGaugePage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Arc Power Gauge',
    path: 'assets/quickjs_ui/arc_gauge_page.mjs',
  );
}

class QuickjsUiSnappableDustPage extends StatelessWidget {
  const QuickjsUiSnappableDustPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Snappable Dust',
    path: 'assets/quickjs_ui/snappable_dust_page.mjs',
  );
}

class QuickjsUiUniversalEffectsPage extends StatelessWidget {
  const QuickjsUiUniversalEffectsPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Universal Node Effects',
    path: 'assets/quickjs_ui/universal_effects_page.mjs',
  );
}

class QuickjsUiControlStatesSlotsPage extends StatelessWidget {
  const QuickjsUiControlStatesSlotsPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Control States + Slots',
    path: 'assets/quickjs_ui/control_states_slots_page.mjs',
  );
}

class QuickjsUiControlStateTransitionsPage extends StatelessWidget {
  const QuickjsUiControlStateTransitionsPage({super.key});

  @override
  Widget build(BuildContext context) => const _ParticleDemoPage(
    title: 'Control State Motion',
    path: 'assets/quickjs_ui/control_state_transitions_page.mjs',
  );
}

class _ParticleDemoPage extends StatelessWidget {
  const _ParticleDemoPage({required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF020617),
        foregroundColor: Colors.white,
      ),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'QuickJS UI particle demo error: $error',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
