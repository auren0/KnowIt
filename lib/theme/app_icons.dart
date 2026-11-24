import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

/// One icon language for KnowIt. Screens reference semantic names instead of
/// mixing Material and Fluent glyphs, so sizes, weights and meanings stay
/// consistent.
abstract final class AppIcons {
  // Navigation (regular unselected, filled selected).
  static const IconData collections = FluentIcons.collections_24_regular;
  static const IconData collectionsSelected = FluentIcons.collections_24_filled;
  static const IconData browse = FluentIcons.search_24_regular;
  static const IconData browseSelected = FluentIcons.search_24_filled;
  static const IconData create = FluentIcons.sparkle_24_regular;
  static const IconData createSelected = FluentIcons.sparkle_24_filled;
  static const IconData statistics = FluentIcons.chart_multiple_24_regular;
  static const IconData statisticsSelected =
      FluentIcons.chart_multiple_24_filled;
  static const IconData settings = FluentIcons.settings_24_regular;
  static const IconData settingsSelected = FluentIcons.settings_24_filled;

  // Generic actions.
  static const IconData add = FluentIcons.add_24_regular;
  static const IconData addCircle = FluentIcons.add_circle_24_regular;
  static const IconData subtract = FluentIcons.subtract_24_regular;
  static const IconData subtractCircle = FluentIcons.subtract_circle_24_regular;
  static const IconData close = FluentIcons.dismiss_24_regular;
  static const IconData clear = FluentIcons.dismiss_circle_20_regular;
  static const IconData check = FluentIcons.checkmark_24_regular;
  static const IconData checkCircle = FluentIcons.checkmark_circle_24_regular;
  static const IconData error = FluentIcons.error_circle_24_regular;
  static const IconData info = FluentIcons.info_24_regular;
  static const IconData warning = FluentIcons.warning_24_regular;
  static const IconData question = FluentIcons.question_circle_24_regular;
  static const IconData edit = FluentIcons.edit_20_regular;
  static const IconData delete = FluentIcons.delete_20_regular;
  static const IconData copy = FluentIcons.copy_20_regular;
  static const IconData move = FluentIcons.arrow_swap_20_regular;
  static const IconData save = FluentIcons.save_24_regular;
  static const IconData undo = FluentIcons.arrow_undo_24_regular;
  static const IconData refresh = FluentIcons.arrow_clockwise_24_regular;
  static const IconData more = FluentIcons.more_horizontal_20_regular;
  static const IconData chevronRight = FluentIcons.chevron_right_20_regular;
  static const IconData chevronLeft = FluentIcons.chevron_left_20_regular;
  static const IconData chevronDown = FluentIcons.chevron_down_20_regular;
  static const IconData arrowLeft = FluentIcons.arrow_left_24_regular;

  // Navigation / structure.
  static const IconData folder = FluentIcons.folder_24_regular;
  static const IconData folderOpen = FluentIcons.folder_open_24_regular;
  static const IconData folderAdd = FluentIcons.folder_add_24_regular;
  static const IconData folderMissing =
      FluentIcons.folder_prohibited_24_regular;
  static const IconData subfolder = FluentIcons.organization_20_regular;
  static const IconData collection = FluentIcons.collections_24_regular;
  static const IconData book = FluentIcons.book_24_regular;
  static const IconData bookOpen = FluentIcons.book_open_24_regular;
  static const IconData bookQuestion =
      FluentIcons.book_question_mark_24_regular;
  static const IconData brain = FluentIcons.brain_circuit_24_regular;
  static const IconData library = FluentIcons.library_24_regular;
  static const IconData archive = FluentIcons.archive_24_regular;
  static const IconData box = FluentIcons.box_24_regular;
  static const IconData document = FluentIcons.document_24_regular;
  static const IconData documentText = FluentIcons.document_text_24_regular;
  static const IconData documentList =
      FluentIcons.document_bullet_list_24_regular;
  static const IconData note = FluentIcons.note_24_regular;

  // Study.
  static const IconData play = FluentIcons.play_24_regular;
  static const IconData playCircle = FluentIcons.play_circle_24_regular;
  static const IconData schedule = FluentIcons.calendar_clock_24_regular;
  static const IconData quick = FluentIcons.flash_24_regular;
  static const IconData cram = FluentIcons.fire_24_regular;
  static const IconData random = FluentIcons.arrow_repeat_all_24_regular;
  static const IconData difficult = FluentIcons.arrow_trending_24_regular;
  static const IconData eye = FluentIcons.eye_24_regular;
  static const IconData eyeOff = FluentIcons.eye_off_24_regular;
  static const IconData tap = FluentIcons.tap_single_24_regular;
  static const IconData cloze = FluentIcons.text_bullet_list_24_regular;
  static const IconData reversed = FluentIcons.arrow_repeat_all_24_regular;
  static const IconData card = FluentIcons.slide_text_24_regular;

  // Search / filters.
  static const IconData search = FluentIcons.search_20_regular;
  static const IconData sort = FluentIcons.arrow_sort_24_regular;
  static const IconData filter = FluentIcons.filter_24_regular;
  static const IconData options = FluentIcons.options_24_regular;
  static const IconData tag = FluentIcons.tag_20_regular;

  // Statistics.
  static const IconData streak = FluentIcons.fire_20_regular;
  static const IconData reviews = FluentIcons.task_list_ltr_20_regular;
  static const IconData percent = FluentIcons.number_symbol_20_regular;
  static const IconData timer = FluentIcons.timer_20_regular;
  static const IconData insights = FluentIcons.data_trending_24_regular;
  static const IconData heatmap = FluentIcons.grid_24_regular;

  // Settings / data.
  static const IconData reminder = FluentIcons.clock_alarm_20_regular;
  static const IconData cloudOff = FluentIcons.cloud_off_24_regular;
  static const IconData cloudUpload = FluentIcons.cloud_arrow_up_24_regular;
  static const IconData download = FluentIcons.arrow_download_24_regular;
  static const IconData upload = FluentIcons.arrow_upload_24_regular;
  static const IconData history = FluentIcons.history_24_regular;
  static const IconData key = FluentIcons.key_24_regular;
  static const IconData lock = FluentIcons.lock_closed_24_regular;
  static const IconData shield = FluentIcons.shield_24_regular;
  static const IconData language = FluentIcons.local_language_24_regular;
  static const IconData translate = FluentIcons.translate_24_regular;
  static const IconData font = FluentIcons.text_font_24_regular;
  static const IconData fontSize = FluentIcons.text_font_size_24_regular;
  static const IconData accent = FluentIcons.color_24_regular;
  static const IconData paint = FluentIcons.paint_brush_24_regular;
  static const IconData theme = FluentIcons.weather_moon_24_regular;
  static const IconData emoji = FluentIcons.emoji_24_regular;
  static const IconData offline = FluentIcons.cloud_off_24_regular;

  // Media / editor.
  static const IconData image = FluentIcons.image_20_regular;
  static const IconData imageOff = FluentIcons.image_off_20_regular;
  static const IconData pause = FluentIcons.pause_circle_24_regular;
  static const IconData audio = FluentIcons.music_note_2_20_regular;
  static const IconData bold = FluentIcons.text_bold_20_regular;
  static const IconData italic = FluentIcons.text_italic_20_regular;
  static const IconData underline = FluentIcons.text_underline_20_regular;
  static const IconData highlight = FluentIcons.highlight_20_regular;
  static const IconData code = FluentIcons.code_20_regular;
  static const IconData lightbulb = FluentIcons.lightbulb_24_regular;
  static const IconData sparkle = FluentIcons.sparkle_24_regular;
  static const IconData sparkleFilled = FluentIcons.sparkle_24_filled;
  static const IconData wand = FluentIcons.wand_24_regular;
}
