# ARCHITECTURE & PATTERNS (GLOBAL)

## 🏛️ CORE PHILOSOPHY (THE FOUR PILLARS)
* **SOLID:** Every class must have a Single Responsibility. Open for extension, closed for modification.
* **DRY (Don't Repeat Yourself):** Abstract shared logic into the **Application Layer** or **Infrastructure Helpers**.
* **KISS (Keep It Simple, Stupid):** Prioritize readability over "clever" code. If a junior developer cannot understand it, refactor.
* **YAGNI (You Ain't Gonna Need It):** Do not build features or abstractions for "future possibilities" unless they are explicitly in the current sprint's plan.

## 🛠️ DESIGN PATTERN STRATEGY
* **Proactive Identification:** During the `superpowers:brainstorming` and `superpowers:writing-plans` phases, identify if a complex structure requires a Design Pattern.
* **Pattern Selection:**
    * **Creation:** Use **Factory** or **Builder** for complex object graphs (e.g., complex configurations or multi-step builders).
    * **Behavioral:** Use **Strategy** for varying business rules (e.g., different Point calculation algorithms) or **Observer** for Event-Driven flows.
    * **Structural:** Use **Repository & Unit of Work** (Mandatory) for database abstraction in the Infrastructure layer.
* **Implementation Directive:** If a pattern is identified as necessary for the current task, it **MUST** be included in the implementation plan. Once the plan is approved, implement the pattern fully as part of the feature set.

## 🏗️ DOMAIN-DRIVEN DESIGN (DDD) LIGHT
* **Entities & Value Objects:** Use **Value Objects** (immutable types — records, data classes, value objects) for logic that doesn't have an identity (e.g., Address, Money, Color).
* **Domain Events:** Use `IDomainEvent` to trigger side effects (Points, Notifications) via the **Application Layer** consumers, keeping the Domain pure.
* **Aggregates:** Ensure that the `UnitOfWork` maintains the consistency of related entities within a single transaction.

## ⚡ SUPERPOWERS ENFORCEMENT
* **Pattern Justification:** When proposing a pattern in a `superpowers:writing-plans` output, provide a one-sentence justification explaining which SOLID principle it upholds.
* **Refactoring vs. Patterns:** If existing code violates **KISS** due to complexity, use the `superpowers:writing-plans` skill to propose a pattern-based refactoring before adding new features.