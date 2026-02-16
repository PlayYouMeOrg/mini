const prompts = [
  "Golden Hour Drift",
  "Dreamline Echo",
  "Neon Orchard",
  "Sunset Vectors",
  "Quiet Frequency",
  "Velvet Coast",
  "Luma Circuit",
  "Tideglass",
  "Afterlight",
  "Static Bloom",
  "Mirage Pattern",
  "Night Palette"
];

const palettePool = [
  ["#f8d184", "#f17456", "#911f27", "#2d3047", "#307473"],
  ["#ffd166", "#ef476f", "#6d597a", "#355070", "#1b4332"],
  ["#f4a261", "#e76f51", "#8ecae6", "#457b9d", "#1d3557"],
  ["#ff9f1c", "#ffbf69", "#cbf3f0", "#2ec4b6", "#011627"],
  ["#f94144", "#f9844a", "#f9c74f", "#90be6d", "#577590"]
];

const TIMER_SECONDS = 15;
const MAX_STACK_SIZE = 4;

const stack = document.querySelector("#cardStack");
const template = document.querySelector("#cardTemplate");
const nextBtn = document.querySelector("#nextBtn");

let cooldownSecondsLeft = 0;
let cooldownTimerId;

function randomInt(max) {
  return Math.floor(Math.random() * max);
}

function randomBetween(min, max) {
  return Math.random() * (max - min) + min;
}

function shuffle(items) {
  return [...items].sort(() => Math.random() - 0.5);
}

function randomGradient() {
  const colors = shuffle(palettePool[randomInt(palettePool.length)]).slice(0, 4);
  const blobs = colors
    .map(
      (color) =>
        `radial-gradient(circle at ${randomBetween(10, 90).toFixed(1)}% ${randomBetween(10, 90).toFixed(1)}%, ${color} 0 22%, transparent 62%)`
    )
    .join(", ");

  const backgroundTilt = `${randomBetween(0, 360).toFixed(0)}deg`;
  return `${blobs}, linear-gradient(${backgroundTilt}, ${colors.join(",")})`;
}

function updateButtonState() {
  if (cooldownSecondsLeft <= 0) {
    nextBtn.disabled = false;
    nextBtn.textContent = "Next Card";
    return;
  }

  nextBtn.disabled = true;
  nextBtn.textContent = `Next Card (${cooldownSecondsLeft}s)`;
}

function startCooldown() {
  clearInterval(cooldownTimerId);
  cooldownSecondsLeft = TIMER_SECONDS;
  updateButtonState();

  cooldownTimerId = setInterval(() => {
    cooldownSecondsLeft -= 1;
    updateButtonState();

    if (cooldownSecondsLeft <= 0) {
      clearInterval(cooldownTimerId);
    }
  }, 1000);
}

function createCard() {
  const fragment = template.content.cloneNode(true);
  const card = fragment.querySelector(".polaroid-card");
  const artwork = fragment.querySelector(".artwork");
  const text = fragment.querySelector(".card-text");

  const rotation = randomBetween(-2.8, 2.8).toFixed(2);
  const title = prompts[randomInt(prompts.length)];

  card.style.setProperty("--rotate", `${rotation}deg`);
  card.style.zIndex = String(stack.children.length + 1);
  card.classList.add("is-dropping");

  artwork.style.background = randomGradient();
  artwork.setAttribute("aria-label", title);
  text.textContent = title;

  return card;
}

function trimStack() {
  while (stack.children.length > MAX_STACK_SIZE) {
    stack.removeChild(stack.firstElementChild);
  }

  [...stack.children].forEach((card, index) => {
    const fromTopIndex = stack.children.length - 1 - index;
    card.style.zIndex = String(index + 1);
    card.style.transform = `translateY(${Math.min(fromTopIndex * 0.35, 1.05)}rem) scale(${1 - Math.min(fromTopIndex * 0.018, 0.05)}) rotate(var(--rotate, 0deg))`;
    card.style.opacity = String(1 - Math.min(fromTopIndex * 0.11, 0.32));
  });
}

function showNextCard() {
  if (cooldownSecondsLeft > 0) {
    return;
  }

  const newCard = createCard();
  stack.appendChild(newCard);
  trimStack();
  startCooldown();
}

nextBtn.addEventListener("click", showNextCard);

showNextCard();
