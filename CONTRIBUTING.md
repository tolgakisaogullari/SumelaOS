# Contributing to SumelaOS

Guidelines for adding skills, rules, memory plugins, and improving the framework.

## Adding a New Skill

1. **Create the skill directory:**
   ```bash
   mkdir -p .sumela/skills/<skill-name>
   ```

2. **Write `SKILL.md`** following the format defined in the `writing-skills` skill (`.sumela/skills/writing-skills/SKILL.md`). Required sections:
   - `<skill_header>` — name, description, triggers
   - `<prerequisites>` — what must be true before loading
   - `<execution_workflow>` — step-by-step procedure
   - `<output_format>` — what the agent produces
   - `<error_handling>` — failure modes and fallbacks

3. **Register in `SKILL_REGISTRY.md`** — add a `<skill>` entry under `<available_skills>`:
   ```xml
   <skill activation="lazy">
   <name>your-skill-name</name>
   <description>One-line description matching user intent patterns.</description>
   <path>.sumela/skills/your-skill-name/SKILL.md</path>
   </skill>
   ```
   Use `activation="eager"` only for session-start skills (rare — most skills are `lazy`).

4. **Validate:**
   ```bash
   bash scripts/validate-structure.sh
   ```

## Adding a New Rule

1. **Create the rule file:**
   ```bash
   # For universal rules:
   touch .sumela/rules/your-rule-name.md

   # For stack-specific rules:
   touch .sumela/rules/templates/your-rule-name.md.best-practice
   touch .sumela/rules/templates/your-rule-name.md.empty
   ```

2. **Follow the rule format** — see existing rules in `.sumela/rules/` for structure. Include:
   - Rule name and scope
   - Concrete directives (not guidelines — rules are enforceable)
   - Examples of correct and incorrect patterns

3. **Register in `RULE_REGISTRY.md`** — add a `<rule>` entry under `<available_rules>`:
   ```xml
   <rule activation="universal" applies_phases="all">
   <name>your-rule-name</name>
   <description>When to load this rule and what it enforces.</description>
   <path>.sumela/rules/your-rule-name.md</path>
   </rule>
   ```

4. **Update `<phase_to_rule_matrix>`** — add your rule to the appropriate phase rows.

5. **Validate:**
   ```bash
   bash scripts/validate-structure.sh
   ```

## Creating a Memory Plugin

1. **Create the plugin directory:**
   ```bash
   mkdir -p .sumela/memory-plugins/<plugin-name>/scripts
   ```

2. **Write required files:**
   - `SKILL.md` — routing triggers, commands, prerequisites (same format as skills)
   - `README.md` — setup instructions, configuration, troubleshooting
   - `requirements.txt` — Python dependencies (one per line)
   - `scripts/` — executable scripts the agent invokes

3. **Register in `SKILL_REGISTRY.md`** — add a `<skill>` entry pointing to the plugin's `SKILL.md`:
   ```xml
   <skill activation="lazy">
   <name>your-plugin-name</name>
   <description>Memory plugin — see `.sumela/memory-plugins/your-plugin-name/SKILL.md` for routing and prerequisites.</description>
   <path>.sumela/memory-plugins/your-plugin-name/SKILL.md</path>
   </skill>
   ```

4. **Test the health check** — document a verify command in `README.md` that users can run to confirm the plugin works.

## PR Process

1. **Fork** the repository.
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feat/your-skill-name
   ```
3. **Make your changes** — skills, rules, or plugins.
4. **Validate structure:**
   ```bash
   bash scripts/validate-structure.sh
   ```
5. **Commit** with Conventional Commits format:
   ```
   feat(skill): add your-skill-name
   fix(rule): correct phase matrix for backend_standards
   docs(plugin): update qdrant setup instructions
   ```
6. **Open a PR** against `main` with:
   - Description of what the skill/rule/plugin does
   - Which triggers or phases it covers
   - Any new dependencies or prerequisites

## Code of Conduct

Be constructive. Assume good intent. Focus on making the framework better for all agents and users.

## Questions?

Open an issue or start a discussion in the repository.
