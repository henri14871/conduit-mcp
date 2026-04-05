import rawApiData from "./api-data.json";

interface ApiClass {
  name: string;
  superclass?: string;
  properties: ApiMember[];
  methods: ApiMember[];
  events: ApiMember[];
}

interface ApiMember {
  name: string;
  type?: string;
  parameters?: Array<{ name: string; type: string }>;
  returnType?: string;
  description?: string;
  tags?: string[];
}

interface ApiEnum {
  name: string;
  items: Array<{ name: string; value: number }>;
}

interface ApiData {
  classes: ApiClass[];
  enums: ApiEnum[];
}

const apiData: ApiData = rawApiData as ApiData;

export interface SearchResult {
  type: "class" | "property" | "method" | "event" | "enum";
  className?: string;
  name: string;
  detail: string;
}

export function searchApi(query: string, maxResults: number = 20): SearchResult[] {
  const data = apiData;
  const q = query.toLowerCase();
  const results: SearchResult[] = [];

  for (const cls of data.classes) {
    if (cls.name.toLowerCase().includes(q)) {
      const props = cls.properties.map((p) => p.name).join(", ");
      const methods = cls.methods.map((m) => m.name).join(", ");
      results.push({
        type: "class",
        name: cls.name,
        detail: `Inherits: ${cls.superclass ?? "none"}\nProperties: ${props || "none"}\nMethods: ${methods || "none"}`,
      });
    }

    for (const prop of cls.properties) {
      if (prop.name.toLowerCase().includes(q)) {
        results.push({
          type: "property",
          className: cls.name,
          name: prop.name,
          detail: `${cls.name}.${prop.name}: ${prop.type ?? "unknown"}${prop.tags?.length ? ` [${prop.tags.join(", ")}]` : ""}`,
        });
      }
    }

    for (const method of cls.methods) {
      if (method.name.toLowerCase().includes(q)) {
        const params = method.parameters
          ?.map((p) => `${p.name}: ${p.type}`)
          .join(", ") ?? "";
        results.push({
          type: "method",
          className: cls.name,
          name: method.name,
          detail: `${cls.name}:${method.name}(${params}): ${method.returnType ?? "void"}`,
        });
      }
    }

    for (const event of cls.events) {
      if (event.name.toLowerCase().includes(q)) {
        results.push({
          type: "event",
          className: cls.name,
          name: event.name,
          detail: `${cls.name}.${event.name}`,
        });
      }
    }

    if (results.length >= maxResults * 3) break; // early exit for large datasets
  }

  for (const en of data.enums) {
    if (en.name.toLowerCase().includes(q)) {
      const items = en.items.map((i) => i.name).join(", ");
      results.push({
        type: "enum",
        name: en.name,
        detail: `Enum.${en.name}: ${items}`,
      });
    }
  }

  // Sort: exact matches first, then by name length
  results.sort((a, b) => {
    const aExact = a.name.toLowerCase() === q ? 0 : 1;
    const bExact = b.name.toLowerCase() === q ? 0 : 1;
    if (aExact !== bExact) return aExact - bExact;
    return a.name.length - b.name.length;
  });

  return results.slice(0, maxResults);
}

export function formatSearchResults(results: SearchResult[]): string {
  if (results.length === 0) {
    return "*No results found. Try a different search term.*";
  }

  const lines: string[] = [];
  for (const r of results) {
    const prefix = r.type.charAt(0).toUpperCase() + r.type.slice(1);
    lines.push(`### ${prefix}: ${r.name}`);
    lines.push(r.detail);
    lines.push("");
  }

  return lines.join("\n");
}
