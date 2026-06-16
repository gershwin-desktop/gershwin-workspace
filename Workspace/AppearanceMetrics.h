//
// AppearanceMetrics.h
//
// Global appearance metrics for the theme, following documented HIG values.
// These values MUST be used wherever possible, e.g., for alert panels, dialogs, and other window types.
// Design rules are described in the comments of this file, they MUST be followed when creating or updating UI elements.
// Do NOT hardcode any layout values in the code, use these constants or create additional ones here instead.
//

#ifndef APPEARANCE_METRICS_H
#define APPEARANCE_METRICS_H

#import <AppKit/AppKit.h>

// Window dimensions
static const float METRICS_WIN_MIN_WIDTH = 500.0;
static const float METRICS_WIN_MIN_HEIGHT = 100.0;

// Icon size for dialogs and alerts shall be 64x64px
static const float METRICS_ICON_SIDE = 64.0;
static const float METRICS_ICON_LEFT = 24.0;
static const float METRICS_ICON_TOP = 24.0;

// Text from left window edge if icon is present
// 24px left margin + 64px icon + 16px gap = shall be 104px left edge for title and message
static const float METRICS_TEXT_LEFT = 104.0;

// Vertical spacing between multiple text elements shall be 8px
static const float METRICS_TITLE_MESSAGE_GAP = 8.0; 

// Vertical spacing between multiple buttons shall be 12px
static const float METRICS_BUTTON_VERT_INTERSPACE = 12.0;
// Horizontal spacing between multiple buttons shall be 10px
static const float METRICS_BUTTON_HORIZ_INTERSPACE = 10.0;

// Normal buttons shall always be 20px high (resize any buttons requested to be 19-24px high to be 20px)
// unless they contain an icon, in which case they may be higher if needed
static const float METRICS_BUTTON_HEIGHT = 20.0;

// Small buttons shall always be 17px high (resize any buttons requested to be 14-18px high to be 17px)
static const float METRICS_BUTTON_SMALL_HEIGHT = 17.0;

// Standard minimum button width shall be 69px
static const float METRICS_BUTTON_MIN_WIDTH = 69.0;

// Margin between content and window edge shall be 15px at the top, 24px at the sides, and 20px at the bottom
static const float METRICS_CONTENT_TOP_MARGIN = 15.0;
static const float METRICS_CONTENT_SIDE_MARGIN = 24.0;
static const float METRICS_CONTENT_BOTTOM_MARGIN = 20.0;

// Radio buttons and checkboxes shall be 18x18px
static const float METRICS_RADIO_BUTTON_SIZE = 18.0;
// Line spacing for the label text of radio buttons and checkboxes shall be 20px (baseline to baseline, not whitespace)
static const float METRICS_RADIO_BUTTON_LINE_SPACING = 20.0;

// Small radio buttons and checkboxes shall be 14x14px
static const float METRICS_RADIO_BUTTON_SMALL_SIZE = 14.0;
// Line spacing for the label text of small radio buttons and checkboxes shall be 18px (baseline to baseline, not whitespace)
static const float METRICS_RADIO_BUTTON_SMALL_LINE_SPACING = 18.0;

// Screen size scaling factor
static const float METRICS_SIZE_SCALE = 0.6;

// Text input fields shall be 22px high
static const float METRICS_TEXT_INPUT_FIELD_HEIGHT = 22.0;
// When the user selects text in a text input field, the selection rectangle is also 16px high
static const float METRICS_TEXT_INPUT_SELECTION_HEIGHT = 16.0;
// When a text input field has keyboard focus, a dark, translucent rectangle
// (which shall be 2px  wide at the top and 3px wide on the other three sides)
// appears around the outside edge of the field
static const float METRICS_TEXT_INPUT_FOCUS_RING_WIDTH_TOP = 2.0;
static const float METRICS_TEXT_INPUT_FOCUS_RING_WIDTH_SIDES = 3.0;

// Tabs shall be 30px high
static const float METRICS_TAB_HEIGHT = 30.0;

// Small tabs shall be 25px high
static const float METRICS_TAB_SMALL_HEIGHT = 25.0;

// Scroll bar width shall be 11px
#define METRICS_SCROLLBAR_WIDTH 11.0

// Resize zone metrics
// Corner zones (NW, NE, SE, SW) - small invisible capture areas
#define METRICS_RESIZE_CORNER_SIZE 6.0
// Edge zones (N, S, E, W) are thin but usable
static const float METRICS_RESIZE_EDGE_THICKNESS = 4.0;
// Grow box zone size (matches actual scroller width for visual consistency)
#define METRICS_GROW_BOX_SIZE 16.0

// Window corner radii for rounded corners
static const float METRICS_TITLEBAR_CORNER_RADIUS = 7.0;  // Optically matches Menu app corner radius
static const float METRICS_WINDOW_BOTTOM_CORNER_RADIUS = 0.0;
static const float METRICS_TITLEBAR_HEIGHT = 22.0;
// TODO: Remove the following 2 lines once WindowManager has been updated
static const float METRICS_TITLEBAR_EDGE_BUTTON_WIDTH = 22.0;      // TODO: Remove
static const float METRICS_TITLEBAR_RIGHT_REGION_WIDTH = 44.0;     // TODO: Remove
static const float METRICS_TITLEBAR_BUTTON_INNER_RADIUS = METRICS_TITLEBAR_CORNER_RADIUS;      // Rounded corner on inner edge only
static const float METRICS_TITLEBAR_ICON_STROKE = 1.5;              // Stroke width for button icons
static const float METRICS_TITLEBAR_ICON_INSET = 9.0;               // Inset from button edges to icon

// Titlebar orb button metrics (round traffic-light buttons, all on left)
static const float METRICS_TITLEBAR_ORB_BUTTON_SIZE = 15.0;
static const float METRICS_TITLEBAR_ORB_PADDING_LEFT = 10.5;
static const float METRICS_TITLEBAR_ORB_BUTTON_SPACING = 4.0;
static const float METRICS_TITLEBAR_ORB_REGION_WIDTH = 68.0;    // Left region reserved for 3 orbs + padding

// Control Positioning in Dialogs
// All spacing between dialog elements shall be a multiple of 4px (4, 8, 12, 16, 20, or 24).
// Guidelines:
// - No space between window edge and scroll bars or frame for single-view document windows.
// - For mixed control dialogs, maintain: 
//   - 16px vertical space between controls,
//   - 24px from window edges to controls,
//   - 20px from the bottom edge to controls (including button shadows).
// - Top spacing depends on the closest control (e.g., 20px for pop-up menus, 16px for tab controls).
// - Aim for a center-biased layout rather than a left-biased approach.
// - Use spacing to group controls rather than group boxes to reduce visual clutter.
// - No control or label shall be within 16px of a group box's borders.
// Control Spacing Guidelines
// - Group controls shall have 20px of vertical spacing; subgroups within groups shall have 16px.
// - Vertical spacing is determined by the tallest control in the row.
// - Checkboxes and radio buttons are spaced 20px baseline-to-baseline, providing 7px of separation between each control.
// - Text for controls (pop-up buttons, checkbox/radio groups) shall be 8px from the associated control.
// - Bevel button spacing varies: toolbar buttons shall be spaced 8px apart; avoid overlapping smaller buttons in palettes.
// - The OK/default button goes in the lower-right corner; a Cancel button shall be to its left, followed by any alternate buttons.
// - Preferred button order: alternate, Cancel, default, with a minimum of 12px horizontal and 10px vertical spacing between push buttons.
// Control Spacing Guidelines
// - Group controls shall have 20px of vertical spacing; subgroups within groups shall have 16px.
// - Vertical spacing is determined by the tallest control in the row.
// - Checkboxes and radio buttons are spaced 20px baseline-to-baseline, providing 7px of separation between each control.
// - Text for controls (pop-up buttons, checkbox/radio groups) shall be 8px from the associated control.
// - Bevel button spacing varies: toolbar buttons shall be spaced 8px apart; avoid overlapping smaller buttons in palettes.
// - The OK/default button goes in the lower-right corner; a Cancel button shall be to its left, followed by any alternate buttons.
// - Preferred button order: alternate, Cancel, default, with a minimum of 12px horizontal and 10px vertical spacing between push buttons.
// 
// Spacing:
// - 8px: Between a control and its text label or icon.
static const float METRICS_SPACE_8 = 8.0;
// - 12px: Horizontally between push/pop-up buttons, text input fields, labels for control groups, subgroups, and tab control and window top.
static const float METRICS_SPACE_12 = 12.0;
// - 16px: Between group box edges and enclosed controls, between primary control groups, and top edge of window and topmost controls.
static const float METRICS_SPACE_16 = 16.0;
// - 20px: Between window bottom edge and enclosed controls, among control groups without group boxes, and between radio button/checkbox label baselines.
static const float METRICS_SPACE_20 = 20.0;
// - 24px: Between window edges and enclosed controls, and between inset tab panes and window edges.
static const float METRICS_SPACE_24 = 24.0;
//
// Fonts:
// - System Font: Regular, 13 pt
//   - Used for message text in dialogs, default font for lists and tables.
#define METRICS_FONT_SYSTEM_REGULAR_13 ([NSFont systemFontOfSize: 13])
// 
// - System Font (Emphasized): Bold, 13 pt
//   - Use sparingly, such as for titling groups of settings without a group box.
#define METRICS_FONT_SYSTEM_BOLD_13 ([NSFont boldSystemFontOfSize: 13])
// 
// - Small System Font: Regular, 11 pt
//   - Used for informative text, headers in lists, and Help Tags; provides additional info in settings windows.
#define METRICS_FONT_SYSTEM_REGULAR_11 ([NSFont systemFontOfSize: 11])
// 
// - Small System Font (Emphasized): Bold, 11 pt
//   - Same usage as Small System Font, but with emphasis.
#define METRICS_FONT_SYSTEM_BOLD_11 ([NSFont boldSystemFontOfSize: 11])
// 
// - Application Font: Regular, 13 pt
//   - Used throughout applications as the main font.
#define METRICS_FONT_APPLICATION_13 ([NSFont systemFontOfSize: 13])
// 
// - Label Font: Regular, 10 pt
//   - Used for labels with controls (e.g., sliders, icon bevel buttons); shall be used rarely in dialogs.
#define METRICS_FONT_LABEL_10 ([NSFont systemFontOfSize: 10])

// Must not use horizontal lines in dialogs or alert panels, use spacing only

#endif // APPEARANCE_METRICS_H
