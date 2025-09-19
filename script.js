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

// Visual sizing constants shared by the renderer. Keeping the node dimensions
// in a single place makes it easier to tune the layout when tweaking the
// appearance.
const NODE_MAX_WIDTH = 220;
const DEFAULT_NODE_HEIGHT = 80;
const NODE_MARGIN_X = 80;
const NODE_VERTICAL_GAP = 24;

// Spacing constants derived from the node geometry. By tying the horizontal
// spacing to the node's maximum width, we guarantee that branches stay clear of
// each other even when text boxes expand vertically to fit their content.
const H_SPACING = NODE_MAX_WIDTH + NODE_MARGIN_X; // horizontal distance between generations

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

// Cache of measured node sizes (in pixels) keyed by node id. Sizes are updated
// after every render to keep the layout in sync with the text content.
const nodeSizeCache = new Map();

// Debounced scheduling helpers so layout updates triggered by size changes do
// not cause synchronous recursion. Using requestAnimationFrame allows the DOM
// to settle before we measure boxes or perform another render pass.
const scheduleFrame = (typeof window !== 'undefined' && window.requestAnimationFrame)
  ? (callback) => window.requestAnimationFrame(callback)
  : (callback) => setTimeout(callback, 16);

let renderScheduled = false;
let measurementScheduled = false;

function scheduleRender() {
  if (renderScheduled) return;
  renderScheduled = true;
  scheduleFrame(() => {
    renderScheduled = false;
    renderMindMap();
  });
}

function scheduleMeasurement() {
  if (measurementScheduled) return;
  measurementScheduled = true;
  scheduleFrame(() => {
    measurementScheduled = false;
    const changed = updateNodeSizeCache();
    if (changed) {
      scheduleRender();
    }
  });
}

function getNodeBoxSize(node) {
  const cached = nodeSizeCache.get(node.id);
  if (cached) {
    return cached;
  }
  return { width: NODE_MAX_WIDTH, height: DEFAULT_NODE_HEIGHT };
}

function getNodeLayoutHeight(node) {
  const { height } = getNodeBoxSize(node);
  return height + NODE_VERTICAL_GAP;
}

function getClampedBoxWidth(node) {
  const { width } = getNodeBoxSize(node);
  return Math.min(Math.max(width, 80), NODE_MAX_WIDTH);
}

function getClampedBoxHeight(node) {
  const { height } = getNodeBoxSize(node);
  return Math.max(height, 40);
}

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
  const nodeHeight = getNodeLayoutHeight(node);
  if (!node.children || node.children.length === 0) {
    current.height = nodeHeight;
    current.y = yStart + nodeHeight / 2;
    return current.height;
  }
  let y = yStart;
  for (const child of node.children) {
    const childHeight = assignSidePositions(child, depth + 1, y, posMap);
    y += childHeight;
  }
  const totalChildHeight = y - yStart;
  const requiredHeight = Math.max(totalChildHeight, nodeHeight);
  current.height = requiredHeight;
  const extra = requiredHeight - totalChildHeight;
  if (extra > 0 && totalChildHeight > 0) {
    let childStart = yStart + extra / 2;
    for (const child of node.children) {
      const childInfo = posMap[child.id];
      const desiredCenter = childStart + childInfo.height / 2;
      const delta = desiredCenter - childInfo.y;
      if (Math.abs(delta) > 0.1) {
        shiftSubtree(child, posMap, delta);
      }
      childStart += childInfo.height;
    }
  }
  current.y = yStart + requiredHeight / 2;
  return current.height;
}

function shiftSubtree(node, posMap, delta) {
  const info = posMap[node.id];
  info.y += delta;
  if (node.children && node.children.length) {
    node.children.forEach(child => shiftSubtree(child, posMap, delta));
  }
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
    const branchHeight = assignSidePositions(child, 0, yStartLeft, posLeft);
    yStartLeft += branchHeight;
  });
  // Assign positions for right side.
  const posRight = {};
  let yStartRight = 0;
  rightChildren.forEach(child => {
    const branchHeight = assignSidePositions(child, 0, yStartRight, posRight);
    yStartRight += branchHeight;
  });
  // Normalise root child positions so both sides align at y=0.
  const rootLeftY = leftChildren.length > 0 ? posLeft[leftChildren[0].id].y : 0;
  const rootRightY = rightChildren.length > 0 ? posRight[rightChildren[0].id].y : 0;
  // Compute final positions. Root at (0,0).
  positions[rootNode.id] = {
    x: 0,
    y: 0,
    node: rootNode,
    height: getNodeLayoutHeight(rootNode),
    box: getNodeBoxSize(rootNode)
  };
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
  const y = yNorm;
  finalMap[node.id] = { x, y, node, height: info.height, box: getNodeBoxSize(node) };
  if (node.children) {
    node.children.forEach(child => {
      traverseAssignFinal(child, side, posMap, finalMap, rootY);
    });
  }
}

function updateNodeSizeCache() {
  let changed = false;
  const elements = document.querySelectorAll('.node-text');
  elements.forEach(div => {
    const id = parseInt(div.dataset.nodeId, 10);
    if (Number.isNaN(id)) return;
    const fo = div.closest('foreignObject');
    const foRect = fo ? fo.getBoundingClientRect() : null;
    const attrWidth = fo ? parseFloat(fo.getAttribute('width')) || NODE_MAX_WIDTH : NODE_MAX_WIDTH;
    const attrHeight = fo ? parseFloat(fo.getAttribute('height')) || DEFAULT_NODE_HEIGHT : DEFAULT_NODE_HEIGHT;
    const scaleX = foRect && foRect.width ? attrWidth / foRect.width : 1;
    const scaleY = foRect && foRect.height ? attrHeight / foRect.height : 1;
    const rawWidth = Math.max(div.scrollWidth, div.offsetWidth);
    const rawHeight = Math.max(div.scrollHeight, div.offsetHeight);
    const measuredWidth = rawWidth * scaleX;
    const measuredHeight = rawHeight * scaleY;
    const width = Math.min(Math.max(measuredWidth, 80), NODE_MAX_WIDTH);
    const height = Math.max(measuredHeight, 40);
    const prev = nodeSizeCache.get(id);
    if (!prev || Math.abs(prev.width - width) > 0.5 || Math.abs(prev.height - height) > 0.5) {
      nodeSizeCache.set(id, { width, height });
      changed = true;
    }
  });
  return changed;
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
  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  Object.values(positions).forEach(pos => {
    const { x, y } = pos;
    const width = getClampedBoxWidth(pos.node);
    const height = getClampedBoxHeight(pos.node);
    const halfHeight = height / 2;
    const top = y - halfHeight;
    const bottom = y + halfHeight;
    if (top < minY) minY = top;
    if (bottom > maxY) maxY = bottom;
    const circleRadius = 10;
    const circleLeft = x - circleRadius;
    const circleRight = x + circleRadius;
    let left = circleLeft;
    let right = circleRight;
    if (x >= 0) {
      left = Math.min(left, x + 12);
      right = Math.max(right, x + 12 + width);
    } else {
      left = Math.min(left, x - (width + 12));
      right = Math.max(right, x - 12);
    }
    if (left < minX) minX = left;
    if (right > maxX) maxX = right;
  });
  const rootPosition = positions[rootNode.id] || { y: 0 };
  const topSpace = rootPosition.y - minY;
  const bottomSpace = maxY - rootPosition.y;
  if (topSpace < bottomSpace) {
    minY = rootPosition.y - bottomSpace;
  } else {
    maxY = rootPosition.y + topSpace;
  }
  // Extend the computed bounds with extra padding so node shadows and expanded
  // text boxes remain fully visible after zooming or exporting.
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
  // Append foreignObject for editable text. The width is limited by a maximum
  // value but the height grows with the content, so nodes expand naturally.
  const fo = nodeEnter.append('foreignObject')
    .attr('class', 'node-fo')
    .attr('width', NODE_MAX_WIDTH)
    .attr('height', DEFAULT_NODE_HEIGHT);
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
    .style('overflow-y', 'visible')
    .style('display', 'inline-block')
    .style('width', 'auto')
    .style('max-width', '100%')
    .style('min-width', '80px')
    .style('height', 'auto')
    .style('padding', '8px')
    .style('box-sizing', 'border-box')
    .style('border-radius', '10px')
    .style('background', '#ffffff')
    .style('box-shadow', '0 2px 6px rgba(15, 23, 42, 0.12)')
    .style('line-height', '1.3')
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
    // and to the left for left‑side nodes. The offset mirrors the node width to
    // keep spacing symmetric.
    .each(function(d) {
      const width = getClampedBoxWidth(d.node);
      const height = getClampedBoxHeight(d.node);
      d3.select(this)
        .attr('width', width)
        .attr('height', height)
        .attr('x', d.x >= 0 ? 12 : -(width + 12))
        .attr('y', -(height / 2));
    });
  nodeSel.merge(nodeEnter).select('.node-text')
    .each(function(d) {
      const div = this;
      div.textContent = d.node.text;
      div.dataset.nodeId = d.node.id;
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
      scheduleMeasurement();
    });
  nodeSel.exit().remove();
  scheduleMeasurement();
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