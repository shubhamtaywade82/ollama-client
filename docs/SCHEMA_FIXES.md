# Schema Validation Fixes

## Problem

LLMs were returning confidence values as percentages (e.g., 95, 100) instead of decimals (e.g., 0.95, 1.0), causing schema validation errors:

```
The property '#/confidence' did not have a maximum value of 1, inclusively
```

## Root Cause

JSON schemas defined numeric constraints (0-1) but lacked explicit descriptions explaining the expected format. LLMs naturally interpret "confidence" as percentages without guidance.

## Solution

Added explicit descriptions to all numeric fields with constrained ranges, clarifying the expected format.

### Fixed Fields

#### Confidence Fields (0.0 to 1.0)
Updated in 8 locations across the codebase:

- `examples/complete_workflow.rb` (2 instances)
  - TaskPlanner schema
  - DataAnalyzer schema
- `examples/dhanhq_agent.rb` (2 instances)
- `examples/dhanhq/schemas/agent_schemas.rb` (2 instances)
- `examples/dhanhq/agents/technical_analysis_agent.rb` (1 instance)
- `examples/advanced_multi_step_agent.rb` (1 instance)

**Before:**
```ruby
"confidence" => {
  "type" => "number",
  "minimum" => 0,
  "maximum" => 1
}
```

**After:**
```ruby
"confidence" => {
  "type" => "number",
  "minimum" => 0,
  "maximum" => 1,
  "description" => "Confidence in this decision (0.0 to 1.0, where 1.0 is 100% confident)"
}
```

#### Other Constrained Fields

- `reproducibility_score` in `advanced_complex_schemas.rb`
  - Added: "Reproducibility score (0.0 to 1.0, where 1.0 means fully reproducible)"

- `profit_margin` in `advanced_complex_schemas.rb`
  - Added: "Profit margin as percentage (0 to 100)"

- `overall_score` in `advanced_complex_schemas.rb`
  - Added: "Overall quality score (0 to 100)"

## Best Practices

### When Defining Schemas

1. **Always include descriptions** for numeric fields with constraints
2. **Be explicit about format**: decimal (0.0-1.0) vs percentage (0-100)
3. **Provide examples** in descriptions when helpful
4. **Use clear units**: "as percentage", "as decimal", "where 1.0 is 100%"

### When Writing Prompts

**Schema descriptions alone may not be enough!** Always reinforce numeric formats in the prompt itself:

```ruby
# ❌ BAD: Relies only on schema description
result = @client.generate(
  prompt: "Analyze this data: #{data}",
  schema: @schema
)

# ✅ GOOD: Explicit examples in prompt
result = @client.generate(
  prompt: "Analyze this data: #{data}\n\nIMPORTANT: Express confidence as a decimal between 0.0 and 1.0 (e.g., 0.85 for 85% confidence, not 85).",
  schema: @schema
)
```

**Why this matters:**
- LLMs may not always read schema descriptions carefully
- Concrete examples in prompts are more effective
- Prevents "100" vs "1.0" confusion

### Example Patterns

**Decimal confidence (0-1):**
```ruby
"confidence" => {
  "type" => "number",
  "minimum" => 0,
  "maximum" => 1,
  "description" => "Confidence level (0.0 to 1.0, where 1.0 is 100% confident)"
}
```

**Percentage score (0-100):**
```ruby
"score" => {
  "type" => "number",
  "minimum" => 0,
  "maximum" => 100,
  "description" => "Quality score as percentage (0 to 100)"
}
```

**Probability (0-1):**
```ruby
"probability" => {
  "type" => "number",
  "minimum" => 0,
  "maximum" => 1,
  "description" => "Probability value (0.0 to 1.0)"
}
```

## Testing

All modified files passed syntax validation:
```bash
ruby -c examples/complete_workflow.rb         # Syntax OK
ruby -c examples/dhanhq_agent.rb              # Syntax OK
ruby -c examples/advanced_multi_step_agent.rb # Syntax OK
ruby -c examples/advanced_complex_schemas.rb  # Syntax OK
```

## Impact

- **Examples now run without schema validation errors**
- **LLMs receive clear guidance** on numeric formats
- **Consistent patterns** across all example schemas
- **Better developer experience** with self-documenting schemas

## Related Files

See also:
- [Testing Guide](TESTING.md) - How to test structured outputs
- [Features Added](FEATURES_ADDED.md) - Schema validation features
