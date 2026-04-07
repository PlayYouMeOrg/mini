const admin = require("firebase-admin");
const OpenAI = require("openai");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { logger } = require("firebase-functions");

if (!admin.apps.length) {
  admin.initializeApp();
}

const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
const PROMPT_ID = "pmpt_69cdce74c14081939d4ad9b5696a2407093f25c0a1255129";
const PROMPT_VERSION = "1";

exports.generatePairStory = onRequest(
  {
    cors: true,
    region: "us-central1",
    timeoutSeconds: 120,
    secrets: [OPENAI_API_KEY],
  },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    const pairId = String(req.body?.pairId ?? "").trim();
    if (!pairId) {
      res.status(400).json({ error: "pairId is required" });
      return;
    }

    const pairRef = admin.database().ref(`/mini/storyPairs/${pairId}`);

    try {
      const pairSnap = await pairRef.get();
      const pair = pairSnap.val();
      const playersMap = pair?.players ?? {};
      const players = Object.values(playersMap).sort(comparePlayersForPrompt);

      if (players.length !== 2 || !players.every(isReadyPlayer)) {
        const currentResult = normalizeResult(pair?.result);
        res.status(200).json(currentResult ?? { status: "waiting" });
        return;
      }

      const statusRef = pairRef.child("result/status");
      const claim = await statusRef.transaction((current) => {
        if (current === "processing" || current === "complete") {
          return;
        }
        return "processing";
      });

      if (!claim.committed) {
        const existingResultSnap = await pairRef.child("result").get();
        res
          .status(200)
          .json(normalizeResult(existingResultSnap.val()) ?? { status: "processing" });
        return;
      }

      await pairRef.child("result").update({
        status: "processing",
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      });

      const openai = new OpenAI({
        apiKey: OPENAI_API_KEY.value(),
      });

      const variables = buildPromptVariables(players);
      const response = await createPromptResponse(openai, variables);
      const text = extractResponseText(response);

      const completedAt = Date.now();
      await pairRef.child("result").set({
        status: "complete",
        text,
        completedAt,
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      });

      res.status(200).json({
        status: "complete",
        text,
        completedAt,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("generatePairStory failed", { pairId, error: message });

      await pairRef.child("result").set({
        status: "error",
        error: message,
        completedAt: Date.now(),
        updatedAt: admin.database.ServerValue.TIMESTAMP,
      });

      res.status(500).json({
        status: "error",
        error: message,
      });
    }
  }
);

function comparePlayersForPrompt(left, right) {
  return String(left?.playerId ?? "").localeCompare(String(right?.playerId ?? ""));
}

function isReadyPlayer(player) {
  return Boolean(
    player &&
      String(player.name ?? "").trim() &&
      Array.isArray(player.choices) &&
      player.choices.length === 3 &&
      player.choices.every(
        (choice) =>
          choice &&
          String(choice.typeName ?? "").trim() &&
          String(choice.selectedOption ?? "").trim()
      ) &&
      player.completedAt
  );
}

function buildPromptVariables(players) {
  const [playerOne, playerTwo] = players;
  return {
    player_one_name: playerOne.name,
    player_one_answers: formatChoices(playerOne.choices),
    player_two_name: playerTwo.name,
    player_two_answers: formatChoices(playerTwo.choices),
  };
}

function formatChoices(choices) {
  return choices
    .map((choice) => `${choice.typeName}: ${choice.selectedOption}`)
    .join("\n");
}

async function createPromptResponse(openai, variables) {
  try {
    return await openai.responses.create({
      prompt: {
        prompt_id: PROMPT_ID,
        version: PROMPT_VERSION,
        variables,
      },
    });
  } catch (error) {
    if (!shouldRetryPromptKey(error)) {
      throw error;
    }

    return openai.responses.create({
      prompt: {
        id: PROMPT_ID,
        version: PROMPT_VERSION,
        variables,
      },
    });
  }
}

function shouldRetryPromptKey(error) {
  const message = String(error?.message ?? "").toLowerCase();
  return (
    message.includes("prompt_id") ||
    message.includes("unknown parameter") ||
    message.includes("invalid prompt")
  );
}

function extractResponseText(response) {
  if (typeof response?.output_text === "string" && response.output_text.trim()) {
    return response.output_text.trim();
  }

  const fragments = [];
  for (const item of response?.output ?? []) {
    for (const content of item?.content ?? []) {
      const value =
        typeof content?.text === "string"
          ? content.text
          : content?.text?.value;
      if (typeof value === "string" && value.trim()) {
        fragments.push(value.trim());
      }
    }
  }

  if (!fragments.length) {
    throw new Error("OpenAI returned no text output.");
  }

  return fragments.join("\n\n");
}

function normalizeResult(result) {
  if (!result || typeof result !== "object") {
    return null;
  }

  return {
    status: String(result.status ?? "waiting"),
    text: typeof result.text === "string" ? result.text : null,
    error: typeof result.error === "string" ? result.error : null,
    completedAt:
      typeof result.completedAt === "number" ? result.completedAt : null,
  };
}
