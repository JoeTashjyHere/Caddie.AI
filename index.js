const express = require("express");
const fetch = require("node-fetch"); // make sure you ran: npm install node-fetch@2

const app = express();
app.use(express.json());

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

app.post("/api/openai/complete", async (req, res) => {
  try {
    const { system, user } = req.body;

    if (!OPENAI_API_KEY) {
      return res.status(500).json({ error: "Missing OPENAI_API_KEY" });
    }

    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        // change this if your account doesn't have this model
        model: "gpt-4o",
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ]
      })
    });

    const data = await r.json();
    console.log("OpenAI raw response:", JSON.stringify(data, null, 2));

    // if OpenAI said there's an error
    if (data.error) {
      return res.status(500).json({ error: "OpenAI call failed", detail: data.error });
    }

    // if OpenAI returned choices properly
    if (Array.isArray(data.choices) && data.choices.length > 0) {
      const content = data.choices[0].message.content;
      return res.json({ resultJSON: content });
    }

    // fallback
    return res.status(500).json({ error: "Unexpected OpenAI response shape", detail: data });
  } catch (err) {
    console.error("Server error:", err);
    res.status(500).json({ error: "OpenAI call failed", detail: String(err) });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`API running on ${PORT}`));
