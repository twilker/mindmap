# Mind Map Editor Requirements

This document captures the current capabilities of the Mind Map Editor as user stories with acceptance criteria.

## 1. Symmetrical Mind Map Layout

**User Story:**
As a mind map author, I want branches arranged evenly on both sides of the central topic so that complex structures remain readable.

**Acceptance Criteria:**
- Given a mind map with a root node and children, when the map renders, then the children are split between left and right sides based on branch weights to balance the layout.【F:script.js†L167-L246】【F:script.js†L303-L392】
- Given nodes with varying text lengths, when their sizes change, then the layout recalculates node widths/heights and re-renders to avoid overlaps.【F:script.js†L54-L150】【F:script.js†L393-L472】
- Given a mind map with top-level branches, when links are drawn, then each branch’s connectors share a consistent color for visual grouping.【F:script.js†L59-L76】【F:script.js†L520-L541】

## 2. Mind Map Rendering & Autofit

**User Story:**
As a mind map author, I want the diagram to fit within the viewport so that the content is immediately visible.

**Acceptance Criteria:**
- Given a rendered map, when new bounds are computed, then the SVG viewBox margins expand to ensure padding around content.【F:script.js†L439-L520】
- Given the application loads or a new map is set, when autofit is requested, then the zoom transform resets and animates the content into view.【F:script.js†L406-L438】【F:script.js†L472-L520】
- Given the map is exported as SVG, when the file is generated, then it uses the last known content bounds so the output tightly frames the diagram.【F:script.js†L742-L795】

## 3. Node Editing and Text Synchronization

**User Story:**
As a mind map author, I want to edit node text directly on the canvas so that I can iterate quickly.

**Acceptance Criteria:**
- Given a user clicks a node, when the node gains focus, then its text becomes editable in place and updates the underlying data model on input.【F:script.js†L542-L620】
- Given node text changes, when editing stops, then the Markdown representation is regenerated to keep import/export data in sync.【F:script.js†L621-L699】【F:script.js†L700-L740】
- Given the application loads, when no map exists, then a default “Central Topic” root node appears ready for editing.【F:script.js†L876-L897】

## 4. Keyboard-Driven Node Creation

**User Story:**
As a keyboard-focused user, I want shortcuts for adding related ideas so that I can build the map without leaving the keyboard.

**Acceptance Criteria:**
- Given a focused node, when the user presses Enter without Shift, then a sibling node with default text is inserted after the current node (or as a child if on the root) and receives focus.【F:script.js†L579-L620】
- Given a focused node, when the user presses Tab, then a child node with default text is appended and receives focus.【F:script.js†L579-L620】

## 5. Zooming and View Controls

**User Story:**
As a viewer, I want to control the zoom and position of the map so that I can inspect details or the big picture.

**Acceptance Criteria:**
- Given the SVG canvas, when a user scrolls or drags, then D3 zoom and pan interactions adjust the view within configured min/max scales.【F:script.js†L110-L150】【F:script.js†L408-L438】
- Given zoom control buttons, when the user clicks “+” or “−”, then the view smoothly scales in or out; when “Reset” is clicked, the view returns to the saved home transform.【F:script.js†L808-L857】
- Given the zoom resets (home transform), when new content triggers autofit, then the reset button returns to the latest autofitted view.【F:script.js†L406-L438】【F:script.js†L808-L857】

## 6. Importing and Exporting Plain Text

**User Story:**
As a user with existing outlines, I want to import and export Markdown bullet lists so that I can share and edit mind maps with other tools.

**Acceptance Criteria:**
- Given an outline in a `.txt` file using `-` bullets with four-space indents, when imported, then the application parses it into the mind map structure.【F:script.js†L700-L740】【F:script.js†L720-L741】【F:script.js†L757-L778】
- Given a current mind map, when exported as text, then the system generates a Markdown bullet list reflecting the map’s hierarchy.【F:script.js†L700-L741】【F:script.js†L722-L740】【F:script.js†L780-L804】
- Given import/export, when users interact with the hidden Markdown textarea, then it remains synchronized for data persistence while staying invisible in the UI.【F:index.html†L45-L53】【F:style.css†L49-L59】【F:script.js†L700-L740】

## 7. Importing MindMeister `.mind` Files

**User Story:**
As a MindMeister user, I want to import `.mind` files so that I can continue editing them in the web editor.

**Acceptance Criteria:**
- Given a `.mind` file, when selected, then the app unzips `map.json`, converts it to Markdown lines, and rebuilds the mind map.【F:index.html†L27-L36】【F:script.js†L741-L778】
- Given notes in the MindMeister data, when converted, then they append to node titles using `::` so information is preserved.【F:script.js†L722-L740】
- Given a successful import, when rendering completes, then the view autofits and node sizing cache resets to accommodate the new structure.【F:script.js†L741-L778】

## 8. Local Persistence with IndexedDB

**User Story:**
As a returning user, I want to save, load, and delete maps locally so that I can manage multiple projects offline.

**Acceptance Criteria:**
- Given a map name, when saved, then the Markdown snapshot is stored in the `mindmapDB` IndexedDB under the `maps` object store.【F:index.html†L31-L41】【F:script.js†L153-L218】【F:script.js†L796-L839】
- Given saved maps, when the app loads, then the saved list dropdown repopulates from IndexedDB allowing selection.【F:script.js†L153-L218】【F:script.js†L839-L874】
- Given a selection, when “Load” is clicked, then the stored Markdown is parsed back into the live mind map and rendered with autofit.【F:index.html†L31-L41】【F:script.js†L816-L874】
- Given a saved map selected for deletion, when confirmed, then the record is removed from IndexedDB and the list refreshes.【F:index.html†L31-L41】【F:script.js†L821-L874】

## 9. File Input Handling

**User Story:**
As a user importing data, I want clear controls for choosing files so that I can load outlines or MindMeister maps easily.

**Acceptance Criteria:**
- Given the import buttons, when clicked, then the corresponding hidden file inputs clear previous selections and open the file picker.【F:index.html†L23-L36】【F:script.js†L841-L874】
- Given a file is chosen, when the change event fires, then the correct import routine executes for `.txt` or `.mind` files.【F:index.html†L23-L36】【F:script.js†L841-L874】

## 10. Application Structure and Styling

**User Story:**
As a user, I want an intuitive interface so that I understand how to interact with the editor.

**Acceptance Criteria:**
- Given the app loads, when the page renders, then the header describes interaction shortcuts (click, Enter, Tab) and the controls panel shows import/export and persistence options.【F:index.html†L18-L41】
- Given the layout renders, when viewed on desktop or mobile, then the main viewer fills the available space and hides the Markdown textarea from sight.【F:index.html†L42-L53】【F:style.css†L1-L88】
- Given the zoom controls, when positioned, then they float at the bottom-right of the viewer with accessible styling cues.【F:index.html†L42-L48】【F:style.css†L60-L88】
