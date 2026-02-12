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

const CARD_COUNT = 8;

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

function renderCards() {
  const grid = document.querySelector("#cardGrid");
  const template = document.querySelector("#cardTemplate");

  grid.innerHTML = "";

  for (let index = 0; index < CARD_COUNT; index += 1) {
    const fragment = template.content.cloneNode(true);
    const card = fragment.querySelector(".polaroid-card");
    const artwork = fragment.querySelector(".artwork");
    const text = fragment.querySelector(".card-text");

    const rotation = randomBetween(-2.8, 2.8);
    card.style.transform = `rotate(${rotation.toFixed(2)}deg)`;

    const title = prompts[randomInt(prompts.length)];
    artwork.style.background = randomGradient();
    artwork.setAttribute("aria-label", title);
    text.textContent = title;

    grid.appendChild(fragment);
  }
}

renderCards();
