# Modern Web Game

A single-file modernized browser Pong game (HTML/CSS/JS). Includes a Dev Log and Tutorial sections.

## Run locally
Just open `index.html` in a browser.

## Music
Put your audio files in `/music/` and update the select list in the UI if needed.
This repo ships with placeholder filenames only.

## Deploy to GitHub Pages
1. Create a new GitHub repo (e.g., `modern-web-game`).
2. Push the files (see commands below).
3. Pages will build from the `gh-pages` branch automatically via the workflow included here.

### One-time setup & push
```bash
git init
git add .
git commit -m "Initial commit: Modern Web Game"
git branch -M main
# Replace with your repo
git remote add origin https://github.com/YOUR-USER/modern-web-game.git
git push -u origin main
```

### Publish with the provided workflow
This repo includes a GitHub Actions workflow that:
- Builds a Pages artifact from the root (static site)
- Publishes to the `gh-pages` branch

After your first push, go to **Settings → Pages** and ensure "Source: GitHub Actions" is selected.

Once deployed, your site will be available at:
`https://YOUR-USER.github.io/modern-web-game/`
