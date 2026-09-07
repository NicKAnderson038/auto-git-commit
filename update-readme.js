const fs = require("fs");
const path = require("path");

// 1. Get the new version from package.json
const packageJson = require("./package.json");
const version = packageJson.version;

// 2. Read the README file
const readmePath = path.join(__dirname, "README.md");
let readmeContent = fs.readFileSync(readmePath, "utf8");

// 3. Replace a placeholder or use a regex to overwrite an existing version format
// This regex dynamically targets the string: (vX.X.X) or your initial placeholder
const versionRegex = /\(v\d+\.\d+\.\d+\)|\(v%VERSION%\)/g;

if (versionRegex.test(readmeContent)) {
  readmeContent = readmeContent.replace(versionRegex, `(v${version})`);
  fs.writeFileSync(readmePath, readmeContent, "utf8");
  console.log(`Successfully updated README.md to v${version}`);
} else {
  console.error("Could not find version placeholder in README.md");
  process.exit(1);
}
