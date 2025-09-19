// script.js

/*
 * Mind Map Editor with symmetrical layout and in‑place editing.
 *
 * This module implements a simple mind map editor that supports
 * symmetrical layout (branches expand to both left and right of a
 * central root). Nodes can be edited directly within the diagram,
 * with Enter to add a sibling and Tab to add a child. Mind maps can
 * be imported from and exported to plain text (bullet list) and
 * MindMeister's .mind format. Data is persisted in IndexedDB.
 */

// Global state: the current mind map root and next available node id.
let rootNode;
let nextId = 0;

// Spacing constants (feel free to tweak these for different layouts).
const H_SPACING = 180; // horizontal distance between generations
// Vertical distance between siblings; increase this constant to provide more
// space for multi‑line node labels. Larger values help prevent overlapping
// when many nodes have lengthy text. Feel free to adjust if necessary.
const V_SPACING = 80;

// D3 selection for the SVG container.
let svg;
let gLink;
let gNode;
// Predefined color palette for root branches. Feel free to tweak or expand this
// list for additional distinct colors. Colors are applied to links for each
// top‑level branch to mimic the coloured routing in typical mind maps.
const BRANCH_COLORS = [
  '#F44336', // red
  '#9C27B0', // purple
  '#2196F3', // blue
  '#4CAF50', // green
  '#FF9800', // orange
  '#795548', // brown
  '#00BCD4', // cyan
  '#607D8B', // blue grey
  '#E91E63', // pink
  '#3F51B5'  // indigo
];

// Open or create the IndexedDB database.
function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('mindmapDB', 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains('maps')) {
        db.createObjectStore('maps', { keyPath: 'name' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function saveMap(name, content) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('maps', 'readwrite');
    const store = tx.objectStore('maps');
    store.put({ name, content });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function loadMap(name) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('maps', 'readonly');
    const store = tx.objectStore('maps');
    const request = store.get(name);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function deleteMap(name) {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('maps', 'readwrite');
    const store = tx.objectStore('maps');
    store.delete(name);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function listMaps() {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('maps', 'readonly');
    const store = tx.objectStore('maps');
    const names = [];
    const request = store.openCursor();
    request.onsuccess = (event) => {
      const cursor = event.target.result;
      if (cursor) {
        names.push(cursor.key);
        cursor.continue();
      } else {
        resolve(names);
      }
    };
    request.onerror = () => reject(request.error);
  });
}

async function refreshSavedList() {
  const selectEl = document.getElementById('savedSelect');
  selectEl.innerHTML = '';
  const names = await listMaps();
  names.forEach(name => {
    const opt = document.createElement('option');
    opt.value = name;
    opt.textContent = name;
    selectEl.appendChild(opt);
  });
}

// Node constructor. Keeps references to parent and children.
function createNode(text, parent = null) {
  return {
    id: nextId++,
    text,
    children: [],
    parent
  };
}

// Compute the weight (number of leaf nodes) for each node.
function computeWeights(node) {
  if (!node.children || node.children.length === 0) {
    node.weight = 1;
    return 1;
  }
  let sum = 0;
  node.children.forEach(child => {
    sum += computeWeights(child);
  });
  node.weight = sum;
  return sum;
}

// Assign vertical positions within a single side (either left or right).
// Returns total height (sum of weights). Stores temporary properties
// height and y in node objects keyed by id.
function assignSidePositions(node, depth, yStart, posMap) {
  const current = { depth, y: 0, height: 0 };
  posMap[node.id] = current;
  if (!node.children || node.children.length === 0) {
    current.height = 1;
    current.y = yStart + 0.5;
    return 1;
  }
  let y = yStart;
  for (const child of node.children) {
    const childHeight = assignSidePositions(child, depth + 1, y, posMap);
    y += childHeight;
  }
  current.height = y - yStart;
  current.y = (yStart + y) / 2;
  return current.height;
}

// Compute the final x,y coordinates for all nodes.
function computePositions() {
  if (!rootNode) return {};
  const positions = {};
  // If root has no children, just put it at origin.
  if (!rootNode.children || rootNode.children.length === 0) {
    positions[rootNode.id] = { x: 0, y: 0, node: rootNode };
    return positions;
  }
  // Compute weights of root's children.
  rootNode.children.forEach(child => computeWeights(child));
  // Sort children by weight (descending) for balanced assignment.
  const sorted = [...rootNode.children].sort((a, b) => b.weight - a.weight);
  const leftChildren = [];
  const rightChildren = [];
  let sumLeft = 0;
  let sumRight = 0;
  sorted.forEach(child => {
    if (sumLeft <= sumRight) {
      leftChildren.push(child);
      sumLeft += child.weight;
    } else {
      rightChildren.push(child);
      sumRight += child.weight;
    }
  });
  // Assign positions for left side.
  const posLeft = {};
  let yStartLeft = 0;
  leftChildren.forEach(child => {
    assignSidePositions(child, 0, yStartLeft, posLeft);
    yStartLeft += child.weight;
  });
  // Assign positions for right side.
  const posRight = {};
  let yStartRight = 0;
  rightChildren.forEach(child => {
    assignSidePositions(child, 0, yStartRight, posRight);
    yStartRight += child.weight;
  });
  // Normalise root child positions so both sides align at y=0.
  const rootLeftY = leftChildren.length > 0 ? posLeft[leftChildren[0].id].y : 0;
  const rootRightY = rightChildren.length > 0 ? posRight[rightChildren[0].id].y : 0;
  // Compute final positions. Root at (0,0).
  positions[rootNode.id] = { x: 0, y: 0, node: rootNode };
  // Process left side.
  leftChildren.forEach(child => {
    traverseAssignFinal(child, 'left', posLeft, positions, rootLeftY);
  });
  // Process right side.
  rightChildren.forEach(child => {
    traverseAssignFinal(child, 'right', posRight, positions, rootRightY);
  });
  return positions;
}

function traverseAssignFinal(node, side, posMap, finalMap, rootY) {
  const info = posMap[node.id];
  const yNorm = info.y - rootY;
  const x = (info.depth + 1) * H_SPACING * (side === 'left' ? -1 : 1);
  const y = yNorm * V_SPACING;
  finalMap[node.id] = { x, y, node };
  if (node.children) {
    node.children.forEach(child => {
      traverseAssignFinal(child, side, posMap, finalMap, rootY);
    });
  }
}

// Render the mind map based on the current rootNode.
function renderMindMap() {
  if (!svg) {
    svg = d3.select('#mindmapCanvas');
    // Create groups for links and nodes.
    gLink = svg.append('g').attr('class', 'links');
    gNode = svg.append('g').attr('class', 'nodes');
  }
  const positions = computePositions();
  // Compute viewBox to fit content.
  let minX = 0,
    maxX = 0,
    minY = 0,
    maxY = 0;
  Object.values(positions).forEach(({ x, y }) => {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  });
  // Extend the horizontal range to accommodate label boxes that extend beyond
  // the node positions. Each label can extend up to 232px to the left or
  // right of its node (220px width + 12px offset), so add padding before
  // computing the viewBox. Without this, labels on the left side can be
  // clipped outside the viewBox and become invisible.
  const labelPad = 240;
  minX -= labelPad;
  maxX += labelPad;
  const margin = 60;
  const width = maxX - minX || 1;
  const height = maxY - minY || 1;
  svg.attr('viewBox', `${minX - margin} ${minY - margin} ${width + margin * 2} ${height + margin * 2}`);
  // Build links data: for each node (except root) create a link from parent to node.
  const links = [];
  Object.values(positions).forEach(pos => {
    const node = pos.node;
    if (node.parent) {
      const parentPos = positions[node.parent.id];
      links.push({ source: parentPos, target: pos });
    }
  });
  // Assign colours to each top‑level branch (children of root). We'll reuse the
  // same colour for all links that belong to a branch. Compute a mapping from
  // branch node id to a colour from the palette.
  const branchColors = {};
  if (rootNode.children && rootNode.children.length) {
    rootNode.children.forEach((child, idx) => {
      branchColors[child.id] = BRANCH_COLORS[idx % BRANCH_COLORS.length];
    });
  }
  // Helper function to find the root‑level branch id for a given node. If the
  // node is a direct child of root, its own id is used. Otherwise we ascend
  // through its parents until reaching a child of root.
  function getBranchId(node) {
    let current = node;
    while (current && current.parent && current.parent !== rootNode) {
      current = current.parent;
    }
    // If current has parent equal to rootNode, it's a top‑level child. Otherwise
    // current may be the root itself (no parent), in which case we return null.
    return current && current.parent === rootNode ? current.id : null;
  }
  // Prepare link generator for curved (horizontal) links.
  const linkGenerator = d3.linkHorizontal()
    .x(d => d.x)
    .y(d => d.y);
  // JOIN links (using <path> elements for curves). Use branch colour if
  // available, otherwise default to grey.
  const linkSel = gLink.selectAll('path').data(links, d => `${d.source.node.id}-${d.target.node.id}`);
  linkSel.enter()
    .append('path')
    .attr('fill', 'none')
    .attr('stroke-width', 2)
    .merge(linkSel)
    .attr('d', d => linkGenerator({ source: { x: d.source.x, y: d.source.y }, target: { x: d.target.x, y: d.target.y } }))
    .attr('stroke', d => {
      const branchId = getBranchId(d.target.node);
      return branchId && branchColors[branchId] ? branchColors[branchId] : '#888';
    });
  linkSel.exit().remove();
  // JOIN nodes
  const nodeValues = Object.values(positions);
  const nodeSel = gNode.selectAll('g.node').data(nodeValues, d => d.node.id);
  const nodeEnter = nodeSel.enter().append('g').attr('class', 'node');
  // Make the entire node group focusable when clicked. Clicking the circle or empty
  // area will focus the editable text inside the node. This improves usability on
  // left‑side nodes where the editable div is offset to the left and might be hard
  // to click precisely.
  nodeEnter.on('click', function(event, d) {
    // Prevent focus change if a text selection is already active within the node.
    // Always call focusOnNode to select the corresponding editable div.
    focusOnNode(d.node.id);
  });
  // Append circles. Attach a click handler so that clicking the circle focuses
  // the editable text associated with this node.
  nodeEnter.append('circle')
    .attr('r', 10)
    .attr('fill', '#4a90e2')
    .on('click', function(event, d) {
      focusOnNode(d.node.id);
    });
  // Append foreignObject for editable text. Increase width slightly for easier editing.
  const fo = nodeEnter.append('foreignObject')
    .attr('class', 'node-fo')
    .attr('width', 220)
    .attr('height', 30);
  // Also attach click handler on the foreignObject itself so that clicking on empty
  // space within it will still focus the node.
  fo.on('click', function(event, d) {
    focusOnNode(d.node.id);
  });
  fo.append('xhtml:div')
    .attr('xmlns', 'http://www.w3.org/1999/xhtml')
    .attr('contenteditable', true)
    .attr('class', 'node-text')
    // Allow multi‑line wrapping and automatic line breaks. Overflow wrap ensures
    // long words break appropriately instead of overflowing into other nodes.
    .style('white-space', 'normal')
    .style('overflow-wrap', 'anywhere')
    .style('outline', 'none')
    .style('cursor', 'text');
  // Update positions for both enter and update selections
  nodeSel.merge(nodeEnter)
    .attr('transform', d => `translate(${d.x},${d.y})`);
  nodeSel.merge(nodeEnter).select('circle')
    .attr('fill', '#4a90e2');
  // Update text content and events
  nodeSel.merge(nodeEnter).select('.node-fo')
    // Position the editable text box to the right of the circle for right‑side nodes
    // and to the left for left‑side nodes. The width of the text box is 220, so
    // offset by 12 to the right and by -(220 + 12) = -232 to the left.
    .attr('x', d => (d.x >= 0 ? 12 : -232))
    .attr('y', -15);
  nodeSel.merge(nodeEnter).select('.node-text')
    .each(function(d) {
      const div = this;
      div.textContent = d.node.text;
      div.dataset.nodeId = d.node.id;
      // Adjust the height of the surrounding foreignObject based on the
      // scrollHeight of the editable div. This allows multi‑line nodes to
      // expand vertically as needed without overlapping neighbouring nodes.
      const foEl = div.parentNode;
      // Set min height to 24px to ensure a single line fits, but allow taller.
      const neededHeight = Math.max(div.scrollHeight, 24);
      d3.select(foEl).attr('height', neededHeight);
    })
    .on('keydown', function(event, d) {
       const id = this.dataset.nodeId;
       const node = findNodeById(rootNode, parseInt(id));
       if (!node) return;
       // If Enter is pressed without Shift, create a sibling. If Shift+Enter,
       // allow a new line to be inserted into the current node. This permits
       // multi‑line text editing without triggering new node creation. Tab
       // creates a child node. Other keys are left untouched.
       if (event.key === 'Enter' && !event.shiftKey) {
         event.preventDefault();
         const newNode = addSibling(node);
         renderMindMap();
         setTimeout(() => focusOnNode(newNode.id), 0);
       } else if (event.key === 'Tab') {
         event.preventDefault();
         const newNode = addChild(node);
         renderMindMap();
         setTimeout(() => focusOnNode(newNode.id), 0);
       }
     })
    .on('input', function(event, d) {
      const id = this.dataset.nodeId;
      const node = findNodeById(rootNode, parseInt(id));
      if (node) {
        node.text = this.textContent;
      }
    });
  nodeSel.exit().remove();
  // Update hidden markdown representation after rendering.
  updateMarkdownInput();
}

// Find a node by id in the tree.
function findNodeById(node, id) {
  if (!node) return null;
  if (node.id === id) return node;
  if (node.children) {
    for (const child of node.children) {
      const res = findNodeById(child, id);
      if (res) return res;
    }
  }
  return null;
}

// Add a sibling node after the specified node.
function addSibling(node) {
  const parent = node.parent;
  if (!parent) {
    // root has no siblings; create new child instead
    return addChild(node);
  }
  const idx = parent.children.indexOf(node);
  const newNode = createNode('New Node', parent);
  parent.children.splice(idx + 1, 0, newNode);
  return newNode;
}

// Add a child node to the specified node.
function addChild(node) {
  const newNode = createNode('New Node', node);
  node.children.push(newNode);
  return newNode;
}

// Focus on a node's editable div by id.
function focusOnNode(id) {
  const div = document.querySelector(`.node-text[data-node-id="${id}"]`);
  if (div) {
    div.focus();
    // Move cursor to end
    const range = document.createRange();
    range.selectNodeContents(div);
    range.collapse(false);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  }
}

// Convert the mind map into Markdown bullet list.
function mindMapToMarkdown(node, depth = 0, lines = []) {
  const indent = ' '.repeat(depth * 4);
  lines.push(`${indent}- ${node.text}`);
  if (node.children) {
    node.children.forEach(child => {
      mindMapToMarkdown(child, depth + 1, lines);
    });
  }
  return lines;
}

function updateMarkdownInput() {
  const textarea = document.getElementById('markdownInput');
  if (!rootNode) {
    textarea.value = '';
    return;
  }
  const lines = mindMapToMarkdown(rootNode);
  textarea.value = lines.join('\n');
}

// Parse a Markdown bullet list into a mind map structure.
function parseMarkdown(text) {
  const lines = text.split(/\r?\n/);
  let currentRoot = null;
  const stack = [];
  lines.forEach(line => {
    const trimmed = line.trim();
    if (!trimmed.startsWith('- ')) return;
    const indentMatch = line.match(/^(\s*)-/);
    const indent = indentMatch ? indentMatch[1].length : 0;
    const depth = Math.floor(indent / 4);
    const title = trimmed.slice(2).trim();
    const node = createNode(title, null);
    if (depth === 0) {
      currentRoot = node;
      stack[0] = node;
      stack.length = 1;
    } else {
      const parent = stack[depth - 1];
      if (!parent) return;
      node.parent = parent;
      parent.children.push(node);
      stack[depth] = node;
      stack.length = depth + 1;
    }
  });
  return currentRoot;
}

// Convert MindMeister JSON to Markdown lines.
function jsonToMarkdown(node, depth = 0, lines = []) {
  const indent = ' '.repeat(depth * 4);
  const title = (node.title || '').trim();
  const note = (node.note || '').replace(/\r?\n/g, ' ').trim();
  let line = `${indent}- ${title}`;
  if (note) line += ` :: ${note}`;
  lines.push(line);
  if (node.children && node.children.length) {
    node.children.forEach(child => jsonToMarkdown(child, depth + 1, lines));
  }
  return lines;
}

// Import MindMeister .mind file.
async function importMindFile(file) {
  if (!file) return;
  try {
    const arrayBuffer = await file.arrayBuffer();
    const zip = await JSZip.loadAsync(arrayBuffer);
    const mapFile = zip.file('map.json');
    if (!mapFile) {
      alert('map.json not found in the .mind file');
      return;
    }
    const jsonStr = await mapFile.async('string');
    const json = JSON.parse(jsonStr);
    const lines = jsonToMarkdown(json.root);
    const markdown = lines.join('\n');
    // parse into mind map
    nextId = 0;
    const parsed = parseMarkdown(markdown);
    if (parsed) {
      rootNode = parsed;
      renderMindMap();
    }
  } catch (err) {
    console.error(err);
    alert('Failed to import .mind file');
  }
}

// Handle import of plain text.
function importTextFile(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    const text = reader.result;
    nextId = 0;
    const parsed = parseMarkdown(text);
    if (parsed) {
      rootNode = parsed;
      renderMindMap();
    }
  };
  reader.readAsText(file);
}

// Export the current mind map as text.
function exportText() {
  const textarea = document.getElementById('markdownInput');
  const blob = new Blob([textarea.value], { type: 'text/plain' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'mindmap.txt';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// Export the current mind map as SVG.
function exportSvg() {
  if (!svg) {
    alert('No mind map to export');
    return;
  }
  // Clone the svg node and serialize it.
  const svgNode = document.getElementById('mindmapCanvas');
  const clone = svgNode.cloneNode(true);
  const serializer = new XMLSerializer();
  let svgString = serializer.serializeToString(clone);
  svgString = '<?xml version="1.0" encoding="UTF-8"?>\n' + svgString;
  const blob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'mindmap.svg';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// UI handlers for save/load/delete.
async function handleSave() {
  const nameInput = document.getElementById('mapNameInput');
  const name = nameInput.value.trim();
  if (!name) {
    alert('Please enter a name for the mind map');
    return;
  }
  const textarea = document.getElementById('markdownInput');
  await saveMap(name, textarea.value);
  await refreshSavedList();
  alert('Mind map saved');
}

async function handleLoad() {
  const selectEl = document.getElementById('savedSelect');
  const name = selectEl.value;
  if (!name) {
    alert('Please select a saved map to load');
    return;
  }
  const record = await loadMap(name);
  if (!record) {
    alert('Map not found');
    return;
  }
  nextId = 0;
  const parsed = parseMarkdown(record.content);
  if (parsed) {
    rootNode = parsed;
    renderMindMap();
  }
}

async function handleDelete() {
  const selectEl = document.getElementById('savedSelect');
  const name = selectEl.value;
  if (!name) {
    alert('Please select a saved map to delete');
    return;
  }
  if (!confirm(`Delete mind map "${name}"?`)) return;
  await deleteMap(name);
  await refreshSavedList();
  alert('Deleted');
}

function setupFileInputs() {
  const txtFileInput = document.getElementById('txtFileInput');
  const mindFileInput = document.getElementById('mindFileInput');
  document.getElementById('importTxtBtn').addEventListener('click', () => {
    txtFileInput.value = '';
    txtFileInput.click();
  });
  txtFileInput.addEventListener('change', (event) => {
    const file = event.target.files[0];
    if (!file) return;
    importTextFile(file);
  });
  document.getElementById('importMindBtn').addEventListener('click', () => {
    mindFileInput.value = '';
    mindFileInput.click();
  });
  mindFileInput.addEventListener('change', (event) => {
    const file = event.target.files[0];
    importMindFile(file);
  });
}

// Initialize the application.
async function init() {
  // Set up buttons and inputs.
  document.getElementById('exportTxtBtn').addEventListener('click', exportText);
  document.getElementById('exportSvgBtn').addEventListener('click', exportSvg);
  document.getElementById('saveMapBtn').addEventListener('click', handleSave);
  document.getElementById('loadMapBtn').addEventListener('click', handleLoad);
  document.getElementById('deleteMapBtn').addEventListener('click', handleDelete);
  setupFileInputs();
  await refreshSavedList();
  // Initialise a default root node.
  nextId = 0;
  rootNode = createNode('Central Topic', null);
  renderMindMap();
}

document.addEventListener('DOMContentLoaded', init);