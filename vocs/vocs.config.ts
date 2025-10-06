import { defineConfig } from 'vocs'
import fs from "fs";
import path from "path";

export default defineConfig({
  title: 'Docs',
  sidebar: [
    {
      text: 'Overview',
      link: '/overview',
    },
    {
      text: 'Getting Started',
      link: '/getting-started',
    },
    {
      text: 'System Permissions',
      link: '/system-permissions',
    },
    {
      text: 'Token Mint',
      link: '/token-mint',
    },
    {
      text: "Guides",
      collapsed: false,
      items: [
        ...fs.readdirSync(path.resolve(process.cwd(), 'docs/pages/guides'))
          .filter((f) => f.endsWith(".mdx"))
          .map((file) => {
            const key = path.basename(file, ".mdx");
            return {
              text: key.split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(" "),
              link: `/guides/${key}`,
            };
          }),
      ],
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
              text: key,
              link: `/technical-reference/${key}`,
            };
          }),
      ],
    }
  ],
})
