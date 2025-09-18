import { defineConfig } from 'vocs'
import fs from "fs";
import path from "path";

export default defineConfig({
  title: 'Docs',
  sidebar: [
    {
      text: 'Getting Started',
      link: '/getting-started',
    },
    {
      text: 'Example',
      link: '/example',
    },
    {
      text: "Technical Reference",
      collapsed: true,
      items: [
        // iterate over all .md files in docs/pages/technical-reference and add them here
        ...fs.readdirSync(path.resolve(process.cwd(), 'docs/pages/technical-reference'))
          .filter((f) => f.endsWith(".md"))
          .map((file) => {
            const key = path.basename(file, ".md");
            return {
              text: key.split(".")[1],
              link: `/technical-reference/${key}`,
            };
          }),
      ],
    }
  ],
})
