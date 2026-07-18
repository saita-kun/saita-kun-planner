# saita-kun-planner (English summary)

## What it is

saita-kun-planner is a free, open-source (Apache-2.0) GitHub template repository that helps small business owners in Japan draft a business plan for Japanese subsidy applications (hojokin, such as the Jizokuka subsidy) using their own Claude Code environment. The kit is free, but using it requires an active Claude Code subscription.

It combines structured specs of official call-for-applications documents, mechanical validators, step-by-step slash commands, and templates — so that the applicant can move from the official guidelines to a reviewable draft, section by section, while staying the author of their own application.

## Who it is for

- Small and medium-sized business owners or sole proprietors in Japan who want to prepare a subsidy application themselves, without outsourcing it.
- Users who have (or can set up) a GitHub account and a Claude Code subscription.
- Note: the subsidy programs covered are Japanese; official documents and the working language of the kit are Japanese.

## Quickstart

Paste the following into your AI assistant (Claude Code / Claude / ChatGPT):

> I want to draft a business plan for a Japanese subsidy application myself.
> Read https://raw.githubusercontent.com/saita-kun/saita-kun-planner/main/docs/ai-agent-guide.md
> and guide me through it, following its steps.

The guide walks your AI through checking prerequisites, creating your own working repository from this template, and running the first commands (`/setup`, then `/start`). Your working repository must be private. If your AI cannot open the URL, open it in your browser yourself and paste the content into the chat.

## Legal scope

This kit operates under strict guardrails aligned with Japanese law (Administrative Scrivener Act / 行政書士法):

- The applicant is the sole author of the application.
- The AI assists with organizing information and drafting; it is not a filing agent and does not submit anything.
- The AI must not guess numbers or requirements.
- Unverified information is marked with [要確認] (a machine-readable marker; do not translate it).
- The official call-for-applications documents always take precedence.
- Completion and submission decisions are made only by the applicant.

## License

Apache-2.0. See [LICENSE](https://github.com/saita-kun/saita-kun-planner/blob/main/LICENSE), [NOTICE](https://github.com/saita-kun/saita-kun-planner/blob/main/NOTICE), and [TRADEMARK.md](https://github.com/saita-kun/saita-kun-planner/blob/main/TRADEMARK.md).

## Language notice

The Japanese [README.md](README.md) is the canonical document; this English page is a summary only. The operational workflow is Japanese: slash commands, customer-facing documents, official subsidy guidelines, and the kit's outputs are all in Japanese.
