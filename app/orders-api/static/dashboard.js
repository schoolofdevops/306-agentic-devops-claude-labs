const REFRESH_INTERVAL = 5000;
const SPARKLINE_POINTS = 30;
const INVENTORY_URL = window.location.hostname === 'localhost'
    ? 'http://localhost:8081'
    : '/proxy/inventory';

const sparklineData = { errors: [], retries: [], latency: [] };

async function fetchJSON(url) {
    try {
        const resp = await fetch(url);
        if (!resp.ok) return null;
        return await resp.json();
    } catch { return null; }
}

function drawSparkline(canvasId, data, color) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    if (data.length < 2) return;

    const max = Math.max(...data, 1);
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    data.forEach((v, i) => {
        const x = (i / (SPARKLINE_POINTS - 1)) * w;
        const y = h - (v / max) * (h - 4) - 2;
        i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    });
    ctx.stroke();
}

function pushSparkline(arr, value) {
    arr.push(value);
    if (arr.length > SPARKLINE_POINTS) arr.shift();
}

async function updateOrdersInfo() {
    const info = await fetchJSON('/api/v1/info');
    if (info) {
        document.getElementById('orders-version').textContent = info.version;
        document.getElementById('orders-hostname').textContent = info.hostname;
        document.getElementById('orders-container').textContent = info.container ? 'Yes' : 'No';
        document.getElementById('orders-k8s').textContent = info.kubernetes ? `${info.namespace}/${info.pod}` : 'No';
    }

    const health = await fetchJSON('/healthz');
    const el = document.getElementById('orders-health');
    el.className = 'status-light ' + (health ? 'healthy' : 'unhealthy');
}

async function updateInventoryInfo() {
    const info = await fetchJSON(INVENTORY_URL + '/api/v1/info');
    if (info) {
        document.getElementById('inventory-version').textContent = info.version;
        document.getElementById('inventory-hostname').textContent = info.hostname;
    }
    const healthEl = document.getElementById('inventory-health');

    const faults = await fetchJSON(INVENTORY_URL + '/admin/faults');
    if (faults && faults.config) {
        const fc = faults.config;
        document.getElementById('fault-status').textContent = fc.enabled
            ? `ON (err:${(fc.error_rate*100).toFixed(0)}% lat:${fc.latency_ms}ms)`
            : 'OFF';
        document.getElementById('fault-status').style.color = fc.enabled ? '#ef4444' : '#22c55e';
        healthEl.className = 'status-light healthy';
    } else {
        healthEl.className = 'status-light unhealthy';
        document.getElementById('fault-status').textContent = 'unreachable';
    }
}

async function updateMetrics() {
    const dashboard = await fetchJSON('/api/v1/dashboard');
    if (dashboard) {
        const retries = dashboard.retry_stats?.recent_retries || 0;
        pushSparkline(sparklineData.retries, retries);
        document.getElementById('retry-count').textContent = retries;
        document.getElementById('retry-count').className = 'metric-value ' + (retries > 5 ? 'danger' : retries > 0 ? 'warning' : 'ok');
        drawSparkline('chart-retries', sparklineData.retries, '#f59e0b');
    }

    const metricsText = await fetch('/metrics').then(r => r.text()).catch(() => '');
    const errorMatch = metricsText.match(/orders_api_upstream_errors_total\{[^}]*\}\s+(\d+)/);
    const errorCount = errorMatch ? parseInt(errorMatch[1]) : 0;
    pushSparkline(sparklineData.errors, errorCount);
    document.getElementById('error-rate').textContent = errorCount;
    document.getElementById('error-rate').className = 'metric-value ' + (errorCount > 10 ? 'danger' : errorCount > 0 ? 'warning' : 'ok');
    drawSparkline('chart-errors', sparklineData.errors, '#ef4444');

    pushSparkline(sparklineData.latency, 0);
    drawSparkline('chart-latency', sparklineData.latency, '#3b82f6');
}

async function updateOrders() {
    const dashboard = await fetchJSON('/api/v1/dashboard');
    const tbody = document.getElementById('orders-tbody');
    if (!dashboard || !dashboard.orders) {
        tbody.innerHTML = '<tr><td colspan="5">No data</td></tr>';
        return;
    }
    if (dashboard.orders.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5">No orders yet</td></tr>';
        return;
    }
    tbody.innerHTML = dashboard.orders.map(o => `
        <tr>
            <td>${o.id}</td>
            <td>${o.product_id}</td>
            <td>${o.quantity}</td>
            <td class="status-${o.status}">${o.status}</td>
            <td>${o.created_at ? new Date(o.created_at).toLocaleTimeString() : '—'}</td>
        </tr>
    `).join('');
}

async function refresh() {
    await Promise.all([updateOrdersInfo(), updateInventoryInfo(), updateMetrics(), updateOrders()]);
    document.getElementById('last-updated').textContent = 'Last updated: ' + new Date().toLocaleTimeString();
}

refresh();
setInterval(refresh, REFRESH_INTERVAL);
