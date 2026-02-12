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

const NEXT_DELAY_SECONDS = 15;

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

function createCard(template) {
  const fragment = template.content.cloneNode(true);
  const card = fragment.querySelector(".polaroid-card");
  const artwork = fragment.querySelector(".artwork");
  const text = fragment.querySelector(".card-text");

  const rotation = randomBetween(-2.8, 2.8).toFixed(2);
  card.style.setProperty("--rotation", `${rotation}deg`);
  card.style.transform = `rotate(${rotation}deg)`;

  const title = prompts[randomInt(prompts.length)];
  artwork.style.background = randomGradient();
  artwork.setAttribute("aria-label", title);
  text.textContent = title;

  return card;
}

function initCardStack() {
  const stack = document.querySelector("#cardStack");
  const template = document.querySelector("#cardTemplate");
  const button = document.querySelector("#nextButton");
  let timer;

  function updateButtonLabel(seconds) {
    if (seconds <= 0) {
      button.textContent = "Next card";
      return;
    }

    button.textContent = `Next card in ${seconds}s`;
  }

  function startCooldown() {
    let remaining = NEXT_DELAY_SECONDS;
    button.disabled = true;
    updateButtonLabel(remaining);

    timer = window.setInterval(() => {
      remaining -= 1;
      updateButtonLabel(remaining);

      if (remaining <= 0) {
        window.clearInterval(timer);
        button.disabled = false;
      }
    }, 1000);
  }

  function dropNextCard() {
    const oldCard = stack.querySelector(".polaroid-card");
    const nextCard = createCard(template);

    if (oldCard) {
      oldCard.classList.add("is-stacked");
      oldCard.addEventListener("animationend", () => oldCard.remove(), { once: true });
    }

    nextCard.classList.add("is-dropping");
    nextCard.addEventListener("animationend", () => {
      nextCard.classList.remove("is-dropping");
    }, { once: true });

    stack.appendChild(nextCard);
    startCooldown();
  }

  button.addEventListener("click", dropNextCard);

  stack.appendChild(createCard(template));
  startCooldown();
}

initCardStack();
