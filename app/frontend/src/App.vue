<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from "vue";

const grafanaUrl = import.meta.env.VITE_GRAFANA_URL || "http://127.0.0.1:3000/d/devops-sushi/devops-sushi";

const status = ref({
  running: false,
  sent: 0,
  ok: 0,
  failed: 0,
  current_rps: null,
  elapsed_seconds: 0,
  duration_seconds: null,
});
const busy = ref(false);
const connected = ref(false);
const message = ref("");
const config = ref({ duration_seconds: 300, min_rps: 5, max_rps: 80, wave: "sine" });
let pollTimer;

const progress = computed(() => {
  if (!status.value.duration_seconds) return 0;
  return Math.min(100, (status.value.elapsed_seconds / status.value.duration_seconds) * 100);
});

const successRate = computed(() => {
  if (!status.value.sent) return "100%";
  return `${((status.value.ok / status.value.sent) * 100).toFixed(1)}%`;
});

async function request(path, options = {}) {
  const response = await fetch(`/load-api${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.detail || "Zahteva ni uspela.");
  return data;
}

async function refreshStatus() {
  try {
    status.value = await request("/status");
    connected.value = true;
  } catch {
    connected.value = false;
  }
}

async function toggleLoad() {
  busy.value = true;
  message.value = "";
  try {
    if (status.value.running) {
      await request("/stop", { method: "POST" });
      message.value = "Pošiljanje requestov je ustavljeno.";
    } else {
      await request("/start", {
        method: "POST",
        body: JSON.stringify({
          ...config.value,
          concurrency: 64,
          request_timeout: 5,
        }),
      });
      message.value = "Sushi requesti so krenili!";
    }
    await refreshStatus();
  } catch (error) {
    message.value = error.message;
  } finally {
    busy.value = false;
  }
}

onMounted(() => {
  refreshStatus();
  pollTimer = window.setInterval(refreshStatus, 1000);
});

onBeforeUnmount(() => window.clearInterval(pollTimer));
</script>

<template>
  <main>
    <nav class="nav shell">
      <a class="brand" href="#" aria-label="DevOps Sushi domov">
        <span class="brand-mark">鮨</span>
        <span>DEVOPS SUSHI</span>
      </a>
      <span class="connection" :class="{ online: connected }">
        <i></i>{{ connected ? "Backend povezan" : "Backend ni dosegljiv" }}
      </span>
    </nav>

    <section class="hero shell">
      <div class="eyebrow">KUBERNETES LOAD KITCHEN · 今日のおすすめ</div>
      <h1>Postrezi requeste.<br /><em>Opazuj sistem.</em></h1>
      <p class="intro">
        Zaženi val prometa proti Sushi API-ju in v Grafani spremljaj,
        kako se odzivajo podi, CPU in metrike.
      </p>

      <div class="actions">
        <button
          class="primary-button"
          :class="{ stop: status.running }"
          :disabled="busy || !connected"
          @click="toggleLoad"
        >
          <span>{{ status.running ? "■" : "▶" }}</span>
          {{ busy ? "Samo trenutek ..." : status.running ? "Ustavi spam" : "Začni spam" }}
        </button>
        <a class="secondary-button" :href="grafanaUrl" target="_blank" rel="noreferrer">
          Odpri Grafano <span>↗</span>
        </a>
      </div>
      <p v-if="message" class="message">{{ message }}</p>
    </section>

    <section class="belt-wrap" aria-label="Animiran sushi tekoči trak">
      <div class="belt" :class="{ fast: status.running }">
        <div v-for="round in 2" :key="round" class="belt-set" aria-hidden="true">
          <div class="plate"><span>🍣</span><small>nigiri</small></div>
          <div class="plate salmon"><span>🍱</span><small>bento</small></div>
          <div class="plate"><span>🍙</span><small>onigiri</small></div>
          <div class="plate green"><span>🍥</span><small>naruto</small></div>
          <div class="plate"><span>🥢</span><small>ready</small></div>
          <div class="plate salmon"><span>🍣</span><small>request</small></div>
        </div>
      </div>
      <div class="belt-base"><span></span><span></span><span></span><span></span><span></span></div>
    </section>

    <section class="dashboard shell">
      <div class="section-heading">
        <div>
          <span class="eyebrow">LIVE SERVICE</span>
          <h2>Stanje obremenitve</h2>
        </div>
        <div class="live-pill" :class="{ active: status.running }">
          <i></i>{{ status.running ? "TEST TEČE" : "PRIPRAVLJEN" }}
        </div>
      </div>

      <div class="stats">
        <article>
          <span>Trenutni RPS</span>
          <strong>{{ status.current_rps ?? "0.0" }}</strong>
          <small>requestov / sekundo</small>
        </article>
        <article>
          <span>Poslani requesti</span>
          <strong>{{ status.sent.toLocaleString("sl-SI") }}</strong>
          <small>v trenutnem testu</small>
        </article>
        <article>
          <span>Uspešnost</span>
          <strong>{{ successRate }}</strong>
          <small>{{ status.failed }} neuspešnih</small>
        </article>
        <article>
          <span>Čas izvajanja</span>
          <strong>{{ Math.floor(status.elapsed_seconds || 0) }}s</strong>
          <small>od {{ status.duration_seconds || config.duration_seconds }} sekund</small>
        </article>
      </div>

      <div class="progress-card">
        <div><span>Napredek testa</span><b>{{ Math.round(progress) }}%</b></div>
        <div class="progress-track"><span :style="{ width: `${progress}%` }"></span></div>
      </div>

      <div class="controls">
        <label>
          <span>Trajanje</span>
          <select v-model.number="config.duration_seconds" :disabled="status.running">
            <option :value="60">1 minuta</option>
            <option :value="180">3 minute</option>
            <option :value="300">5 minut</option>
            <option :value="600">10 minut</option>
          </select>
        </label>
        <label>
          <span>Najmanjši RPS</span>
          <input v-model.number="config.min_rps" type="number" min="1" max="500" :disabled="status.running" />
        </label>
        <label>
          <span>Največji RPS</span>
          <input v-model.number="config.max_rps" type="number" min="1" max="1000" :disabled="status.running" />
        </label>
        <label>
          <span>Oblika vala</span>
          <select v-model="config.wave" :disabled="status.running">
            <option value="sine">Sinusni val</option>
            <option value="sawtooth">Naraščanje</option>
            <option value="step">Koraki</option>
            <option value="random">Naključno</option>
          </select>
        </label>
      </div>
    </section>

    <footer class="shell">SUSHI OBSERVABILITY LAB <span>·</span> FASTAPI <span>·</span> PROMETHEUS <span>·</span> GRAFANA</footer>
  </main>
</template>
