---
name: research
description: Investigate technical, product, vendor, API, library, or architecture questions using current primary sources and provide evidence-linked findings. Use when the user asks for research, a research pass, investigation, current documentation, source comparison, fact verification, or recommendations based on external evidence.
---

# Primary-Source Research

Answer the decision behind the question, not merely the search query.

## Frame the question

State the scope, the decision the research should inform, and what would count as sufficient evidence. Separate current facts from historical context and opinion.

## Use the cheapest trustworthy source

Follow the active workspace research order. For LogueOS, begin with repository canon and local source, then Context7 or ordinary web search for current documentation, then direct primary-source fetching. Use Firecrawl when normal retrieval is insufficient. Use Perplexity only as a last resort and avoid deep-research tiers unless the user explicitly approves the cost.

For technical claims, prefer official documentation, specifications, source repositories, release notes, and first-party APIs. Use secondary sources to discover leads, not as the final authority when a primary source exists.

## Keep evidence attached

Record the source, publication or release date when relevant, and the specific claim it supports. Mark inferences as inferences. Check whether a source describes the current version or an older release.

Compare conflicting sources and explain which one controls. Repository code and live runtime state outrank a stale marketing or tutorial page for implementation claims.

## Deliver the result

Lead with the recommendation or answer. Separate confirmed facts, tradeoffs, uncertainties, and suggested next steps. Cite links close to the claims they support.

Return findings in chat by default. Write a file only when the user requests an artifact or the active workflow requires one, and follow the workspace placement rules before creating it.

