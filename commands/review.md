Perform a comprehensive solution review of the current project.

Break the codebase into manageable sections and evaluate each systematically:

1. **Discovery**: Map the project structure - identify entry points, config, core logic, utils, tests

2. **Section-by-Section Review**: For each major section evaluate:
   - Code quality (readability, duplication, complexity)
   - Architecture (separation of concerns, patterns, scalability)
   - Security (input validation, auth, secrets, OWASP risks)
   - Performance (queries, memory, caching, async)

3. **Copilot Second Opinion**: For each major section, get another model's perspective:
```bash
copilot --model gpt-5.1 -p "Review this code for improvements, risks, and optimizations: [code summary and key files]"
```

4. **Output Format**: For each section:
   - Overview of what it does
   - Strengths
   - Issues (Critical/High/Medium/Low with file:line locations)
   - Copilot's perspective (second opinion)
   - Specific optimizations
   - Risks if not addressed

5. **Final Summary**:
   - Overall assessment
   - Critical issues (fix immediately)
   - High priority improvements
   - Quick wins
   - Technical debt
   - Recommended next steps

Start the review now. If a specific directory or scope is provided as an argument, focus on that: $1
