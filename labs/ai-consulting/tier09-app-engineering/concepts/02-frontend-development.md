# Module 9.2 - Basic Frontend Development

**Read this before you touch the keyboard.** The frontend is the part of your app the user actually sees and clicks. For Project 9 we built it on purpose to be as small as possible - one static HTML page, one CSS file, one JavaScript file, and nothing else. No build tool, no npm install, no framework. The whole thing is three files that a web browser can open and a plain FastAPI server can hand out. That means it runs on a small CentOS box with zero toolchain, it is easy to read end to end, and there is nothing to "compile" or break. This doc teaches you the pieces, always tying back to what Project 9 does, and closes with when you would reach for something bigger.

The three files, and where FastAPI serves them:

```
templates/index.html   -> served at GET /
static/style.css       -> the look (dark theme)
static/app.js          -> the behavior (talks to the API)
```

FastAPI serves `index.html` at the root path and mounts everything under `static/` so the browser can fetch the CSS and JS:

```python
app.mount("/static", StaticFiles(directory="static"), name="static")
```

## 1. HTML

HTML is the structure of the page - the boxes, text, inputs, and buttons. It is not code that "runs"; it is a description of what is on the page. The browser reads it top to bottom and draws it.

The smallest useful HTML tags you need to know:

- `<div>` - a generic container box. We use these as "cards".
- `<input>` - a place to type. `type="email"` and `type="text"` are what we use.
- `<button>` - something to click.
- `<pre>` - preformatted text. Keeps spaces and line breaks exactly, which is perfect for showing an answer or JSON.
- `id="..."` - a unique name so JavaScript can find that element later.

Project 9's `index.html` has exactly three cards:

```html
<div id="login-box">
  <input id="email" type="email" placeholder="you@example.com" />
  <button id="signin">Sign in</button>
</div>

<div id="ask-box" class="hidden">
  <input id="question" type="text" placeholder="Ask a question..." />
  <button id="ask">Ask</button>
  <pre id="answer"></pre>
</div>

<div id="admin-box" class="hidden">
  <input id="doc-title" placeholder="Title" />
  <input id="doc-source" placeholder="Source" />
  <input id="doc-body" placeholder="Body" />
  <button id="enqueue">Enqueue</button>
  <button id="refresh">Refresh queue</button>
  <pre id="queue"></pre>
</div>
```

Notice `class="hidden"` on the ask box and the admin box. They start invisible. JavaScript reveals them after you log in, and the admin box only appears if you are an admin. Why start hidden? Because a logged-out user should not see the ask or admin controls at all. The page ships with everything present but only the login box visible.

## 2. CSS

CSS controls how the HTML looks - colors, spacing, fonts, borders. Without CSS the page still works, it just looks like a plain 1995 document. `static/style.css` is small and hand-written. It sets a dark theme:

```css
body {
  background: #12141a;
  color: #e6e6e6;
  font-family: system-ui, sans-serif;
  max-width: 720px;
  margin: 40px auto;
}

div {
  background: #1c1f27;
  border: 1px solid #2a2f3a;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
}

.hidden { display: none; }
```

That `.hidden { display: none; }` rule is what makes the "hidden" cards disappear. When JavaScript removes the `hidden` class from an element, the card shows up. This is the whole reveal mechanism - no animation library, no state manager, just add or remove one class.

We did not use Tailwind, Bootstrap, or any CSS framework here. Those are great when you have dozens of screens and a team keeping styles consistent, but they add a download and often a build step. For a single page with three cards, a 40-line stylesheet is clearer and faster. Minimal is fine here because the surface is tiny. Reach for a framework when the styling becomes repetitive across many pages, not before.

## 3. JavaScript basics

JavaScript is the only one of the three that actually "runs". It reacts to clicks, reads what you typed, calls the server, and updates the page. A few basics:

- `document.getElementById("ask")` finds the element with that id.
- `.addEventListener("click", fn)` runs `fn` when the element is clicked.
- `.value` reads what is in an input; `.textContent` sets the text of an element.
- `.classList.remove("hidden")` reveals a hidden card; `.classList.add("hidden")` hides it.
- `async`/`await` lets you wait for a network call without freezing the page.

Wiring a button looks like this:

```javascript
document.getElementById("ask").addEventListener("click", async () => {
  const query = document.getElementById("question").value;
  // ... call the API, then show the result
});
```

The `async () => { ... }` is an arrow function that is allowed to `await`. We need `await` because talking to the server takes time and we do not want the browser to lock up while it waits.

## 4. The `api()` helper and API calls

An API call is your JavaScript asking the FastAPI server to do something and send data back. Rather than repeat the same `fetch` boilerplate everywhere, `app.js` defines one small helper:

```javascript
async function api(path, method, body) {
  const res = await fetch(path, {
    method,
    headers: { "Content-Type": "application/json" },
    credentials: "same-origin",
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return { res, data };
}
```

Line by line, why each piece matters:

- `path` is the server route, like `/ask` or `/login`.
- `method` is `POST` or `GET`.
- `JSON.stringify(body)` turns a JavaScript object into a JSON text string, which is what the server expects.
- `credentials: "same-origin"` is the important one. It tells the browser to include the session cookie on requests to the same origin as the page. Because of it, once you log in you stay logged in - the browser attaches the cookie automatically on every call, and you never handle the cookie yourself in JavaScript. Worth knowing: `"same-origin"` is actually the default for `fetch()`, so our page would behave the same without it, but stating it explicitly documents the intent and makes the code robust if anyone ever copies it into a cross-origin setting. For a genuinely cross-origin call you would need `credentials: "include"` AND a matching `Access-Control-Allow-Credentials` header from the server (see: https://developer.mozilla.org/en-US/docs/Web/API/Request/credentials).
- `await res.json()` parses the JSON text the server sent back into a JavaScript object you can use.

We return both `res` and `data`. `res.ok` is a boolean that is true only when the HTTP status is in the 200-299 range (see: https://developer.mozilla.org/en-US/docs/Web/API/Response/ok); `data` is the actual payload. We will use `res.ok` for error handling in section 8.

## 5. Forms

A form is any group of inputs plus a submit action. Ours are not wrapped in a real `<form>` tag - we use loose inputs and a button with a click handler, which is simpler and avoids the browser's default "reload the whole page on submit" behavior.

The pattern for every one of our forms is the same three steps:

1. Read the input values with `.value`.
2. Send them to the server with `api(...)`.
3. Do something with the response.

Login is the smallest example:

```javascript
document.getElementById("signin").addEventListener("click", async () => {
  const email = document.getElementById("email").value;
  const { res, data } = await api("/login", "POST", { email });
  // ... handle the result
});
```

## 6. Login flow and revealing cards

Here is the full login flow, because it drives everything else on the page:

1. User types an email and clicks Sign in.
2. JavaScript calls `POST /login` with `{ email }`.
3. On success the server sets an httponly session cookie and returns `{ username, role }`.
4. JavaScript reveals the ask box for every user, and the admin box only if `role === "admin"`.

```javascript
document.getElementById("signin").addEventListener("click", async () => {
  const email = document.getElementById("email").value;
  const { res, data } = await api("/login", "POST", { email });
  if (!res.ok) {
    document.getElementById("answer").textContent = data.detail;
    return;
  }
  document.getElementById("ask-box").classList.remove("hidden");
  if (data.role === "admin") {
    document.getElementById("admin-box").classList.remove("hidden");
  }
});
```

Two things worth understanding. First, "httponly" means JavaScript cannot read the cookie via `document.cookie` - only the browser and server touch it. That is a security win: even if an attacker sneaks a script onto the page, it cannot steal the session cookie. MDN recommends setting `HttpOnly` on any cookie that does not need JavaScript access precisely to mitigate cross-site scripting (see: https://developer.mozilla.org/en-US/docs/Web/Security/Practical_implementation_guides/Cookies). Second, the role check happens on the client only to decide what to show. The server must still enforce that non-admins cannot call admin routes. Hiding a button is convenience, not security.

## 7. Ask flow

The ask box is the heart of the app. Flow:

1. User types a question and clicks Ask.
2. JavaScript immediately shows "Thinking..." so the user knows something is happening.
3. JavaScript calls `POST /ask` with `{ query }`.
4. When the answer comes back, JavaScript renders the answer text, the citation source names, the `latency_ms`, and the `generator` name.

```javascript
document.getElementById("ask").addEventListener("click", async () => {
  const query = document.getElementById("question").value;
  const out = document.getElementById("answer");
  out.textContent = "Thinking...";
  const { res, data } = await api("/ask", "POST", { query });
  if (!res.ok) {
    out.textContent = "Error: " + data.detail;
    return;
  }
  const sources = data.citations.map(c => c.source).join(", ");
  out.textContent =
    data.answer +
    "\n\nSources: " + sources +
    "\nLatency: " + data.latency_ms + "ms" +
    "\nGenerator: " + data.generator;
});
```

Showing latency and which generator answered is not decoration. When you are building an AI app you want to see, right in the UI, how slow the call was and which model or path produced the answer. That turns the frontend into a debugging tool for the backend.

## 8. User feedback

User feedback is everything the interface does to tell the user what is going on. A slow AI call with no feedback feels broken. We use three cheap techniques:

- Loading states. Setting `out.textContent = "Thinking..."` before the call means the user is never staring at a dead button wondering if it worked.
- Error messages. We check `res.ok`. When it is false, the server put a human-readable reason in `data.detail`, and we show that instead of a silent failure. Never swallow an error - always surface `data.detail`.
- Disabling buttons. For anything that should not be double-clicked, set `button.disabled = true` before the call and `button.disabled = false` after. This stops a user from firing five identical requests by clicking impatiently.

```javascript
const btn = document.getElementById("ask");
btn.disabled = true;
try {
  // ... make the call
} finally {
  btn.disabled = false;
}
```

The `finally` block guarantees the button is re-enabled even if the call throws. Good feedback is the difference between an app that feels reliable and one that feels flaky, and it costs almost nothing to add.

## 9. File upload and the admin dashboard

The admin box is a minimal admin dashboard. It does two jobs.

Enqueue a document. The admin types a title, source, and body, then clicks Enqueue. JavaScript sends those as a JSON object to the ingest endpoint:

```javascript
document.getElementById("enqueue").addEventListener("click", async () => {
  const body = {
    title: document.getElementById("doc-title").value,
    source: document.getElementById("doc-source").value,
    body: document.getElementById("doc-body").value,
  };
  await api("/admin/ingest", "POST", body);
});
```

Refresh the queue. Clicking Refresh queue does a `GET /admin/jobs` and lists each job's id, status, and attempts so the admin can watch documents move through the pipeline:

```javascript
document.getElementById("refresh").addEventListener("click", async () => {
  const { data } = await api("/admin/jobs", "GET");
  document.getElementById("queue").textContent = data.jobs
    .map(j => `${j.id}  ${j.status}  attempts=${j.attempts}`)
    .join("\n");
});
```

That is a dashboard in its simplest honest form: a button that fetches current state and a place to print it. No live websockets, no charts - just refresh and read.

A note on real file upload. We send document text as a JSON body because our documents are typed in by hand. A real file upload - a PDF, a CSV, an image - does not fit in a JSON string. For that you would use an `<input type="file">`, read the chosen file into a `FormData` object, and POST it to a multipart endpoint:

```html
<input type="file" id="doc-file" />
```

```javascript
const fd = new FormData();
fd.append("file", document.getElementById("doc-file").files[0]);
await fetch("/admin/upload", { method: "POST", body: fd, credentials: "same-origin" });
```

Note we deliberately do NOT set `Content-Type` here. When you pass a `FormData` object as the body, the browser sets `Content-Type: multipart/form-data` for you AND appends the `boundary` parameter it will use to separate the parts. MDN warns explicitly against setting it yourself: "do not explicitly set the Content-Type header on the request. Doing so will prevent the browser from being able to set the Content-Type header with the boundary expression it will use to delimit form fields" (see: https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest_API/Using_FormData_Objects). On the server side FastAPI would receive the file with `UploadFile` (see: https://fastapi.tiangolo.com/tutorial/request-files/). We deliberately did not build this in Project 9 because typed-in text kept the whole path JSON and simple, but you should know the multipart pattern exists for when files are involved.

## 10. Chat interfaces

A chat interface is the familiar back-and-forth: you send a message, the assistant replies, and both stay on screen as a growing conversation. The standard pattern is:

1. Append the user's message to the visible conversation.
2. Show a typing or loading indicator.
3. Call the API.
4. Replace the indicator with the assistant's reply, appended below.
5. Keep the history so the next message has context.

Our ask box is the single-turn version of this. It sends one question, shows "Thinking..." (the loading indicator), and prints one answer. It does not keep a running transcript or send prior turns for context. To grow it into a real chat you would keep an array of messages, render each into its own bubble instead of overwriting one `<pre>`, and send the recent history along with each new question so the model remembers the conversation. The building blocks are identical - the only new idea is keeping and displaying a list instead of a single answer.

## 11. Later - when to reach for a framework

We wrote Project 9 in vanilla HTML, CSS, and JavaScript on purpose. The tradeoff: vanilla has zero toolchain, so it runs anywhere - a small CentOS box, no Node, no build step, nothing to break in deploy. The cost is that as an app grows, hand-managing the DOM gets tedious. Here is when you graduate to something bigger:

- React. Reach for it when the UI gets rich and interactive - many components, shared state, pieces that update independently. React keeps the screen in sync with your data so you stop hand-writing `classList.remove("hidden")` for everything. It needs a build tool and a Node toolchain, which is exactly what we were avoiding here.

- Next.js. React plus server-side rendering, routing, and API routes in one framework. Reach for it for a real product with many pages, SEO needs, and server-rendered content. It is heavier still, and total overkill for a three-card internal tool.

- Streamlit. A Python library that builds a web UI from Python code - no HTML, CSS, or JavaScript at all. Reach for it for a fast internal AI demo or data app where you just want widgets and charts around your Python backend. The tradeoff is you get Streamlit's look and its rerun-the-whole-script model, with little control over layout.

- Gradio. Purpose-built for AI demos - drop a text box or file upload in front of a model in a few lines of Python. Reach for it to share a model demo quickly, especially for a Hugging Face style share link. Like Streamlit, you trade fine control for speed.

The rule of thumb: use the lightest thing that does the job. For a single page that logs in, asks one question, and has a small admin panel, vanilla wins because it is readable, dependency-free, and runs on the smallest box we have. Move up to React or Next.js when the interactivity outgrows hand-written DOM code, and to Streamlit or Gradio when you want an AI demo online today and do not care about custom frontend at all.

## References

- MDN - Request: credentials property (`same-origin` is the default; cross-origin needs `include`): https://developer.mozilla.org/en-US/docs/Web/API/Request/credentials
- MDN - Using the Fetch API: https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch
- MDN - Response: ok property (true for status 200-299): https://developer.mozilla.org/en-US/docs/Web/API/Response/ok
- MDN - Using FormData Objects (do not set Content-Type; browser sets the boundary): https://developer.mozilla.org/en-US/docs/Web/API/XMLHttpRequest_API/Using_FormData_Objects
- MDN - Secure cookie configuration (HttpOnly mitigates XSS): https://developer.mozilla.org/en-US/docs/Web/Security/Practical_implementation_guides/Cookies
- MDN - EventTarget.addEventListener: https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener
- FastAPI - Request Files (`UploadFile` for multipart uploads): https://fastapi.tiangolo.com/tutorial/request-files/
- FastAPI - Static Files (`StaticFiles` mount): https://fastapi.tiangolo.com/tutorial/static-files/

Prof. Happy (SUTA Labs)
