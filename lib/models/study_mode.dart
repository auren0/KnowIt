/// Available study modes.
///
/// Only [StudyMode.srs] writes FSRS scheduling state. All other modes are
/// practice modes: they never change a card's due date, stability or
/// difficulty, so a casual session can never damage the review schedule.
enum StudyMode {
  srs(
    label: 'Spaced repetition',
    shortLabel: 'Review',
    description: 'Smart scheduling based on when you are about to forget.',
    icon: 'schedule',
    changesSchedule: true,
  ),
  quick(
    label: 'Quick review',
    shortLabel: 'Quick',
    description:
        'Run through cards that are due, without changing the schedule.',
    icon: 'bolt',
    changesSchedule: false,
  ),
  cram(
    label: 'Cram',
    shortLabel: 'Cram',
    description: 'Study a deck intensively. The schedule stays untouched.',
    icon: 'local_fire_department',
    changesSchedule: false,
  ),
  random(
    label: 'Random practice',
    shortLabel: 'Random',
    description: 'Shuffle every card in the deck and practice freely.',
    icon: 'shuffle',
    changesSchedule: false,
  ),
  difficult(
    label: 'Difficult cards',
    shortLabel: 'Difficult',
    description: 'Focus on cards you keep forgetting.',
    icon: 'trending_up',
    changesSchedule: false,
  );

  const StudyMode({
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.icon,
    required this.changesSchedule,
  });

  final String label;
  final String shortLabel;
  final String description;
  final String icon;
  final bool changesSchedule;

  static StudyMode fromName(String? name) => StudyMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => StudyMode.srs,
  );
}
