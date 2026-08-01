# Chapter 9 — DTO & Contract Library

> *Section file for `GenericProjectGuidlines_V1.10_20260323.md`*
>
> **⚠️ Sync rule — agent instruction:** This is a section file. Any change made here **must be mirrored in the corresponding chapter** of `GenericProjectGuidlines_V1.10_20260323.md`. Any change made in the parent document's corresponding chapter must be mirrored back here. Both files must remain identical in content for their shared sections.
>
> **TOC Maintenance:** If this section is renamed or deleted, update both the parent document's Contents list AND the `GenericProjectGuidlines_TOC.md` file. See the TOC file for detailed maintenance instructions.

---

The `{AppName}.Contracts` library is the formal boundary between the API and all consumers. Domain entities never cross the HTTP boundary; they are always mapped to and from DTOs before leaving or entering the API.

## Why a Separate Contracts Library

| Without Contracts Library | With Contracts Library |
|---------------------------|------------------------|
| Domain changes break website and mobile simultaneously | Domain can change internally without affecting consumers until DTOs are explicitly updated |
| EF Core navigation properties serialize as circular JSON | DTOs contain only the fields needed; no accidental over-serialization |
| MAUI cannot reference Domain due to web framework dependencies | MAUI references only Contracts — pure .NET, no web packages required |
| Swagger schema polluted with EF Core internal attributes | Clean OpenAPI schema generated from DTO shapes only |

## DTO Rules

- **MUST** Every endpoint has a dedicated request DTO and response DTO. Do not reuse the same DTO for both reads and writes.
- **MUST** Response DTOs expose the entity `Guid`, never the integer `Id`. Integer PKs must not appear in any API response or client-facing URL.
- **MUST** Request DTOs carry all validation attributes so validation can be applied identically on the API server and in a MAUI client.
- **MUST** DTOs never contain EF Core attributes, navigation properties, or `DbContext` references.
- **SHOULD** Name patterns: `Create{Entity}RequestDto`, `Update{Entity}RequestDto`, `{Entity}ResponseDto`, `{Entity}SummaryDto` (for list items).
- **SHOULD** Flatten nested data into response DTOs rather than nesting DTOs. Simplifies mobile data binding.
- **MAY** Use a generic `PagedResultDto<T>` wrapper for paginated list endpoints: `{ Items, TotalCount, PageNumber, PageSize }`.

## Example DTO Pair

```csharp
// Contracts/Requests/Coins/CreateCoinRequestDto.cs
public class CreateCoinRequestDto
{
    [Required][MaxLength(255)]
    public string Name { get; set; } = string.Empty;
    [Required]
    public CurrencyCode Currency { get; set; }
    [Range(1800, 2100)]
    public int YearMinted { get; set; }
}

// Contracts/Responses/Coins/CoinResponseDto.cs
public class CoinResponseDto
{
    public Guid      CoinGuid     { get; set; }   // GUID, never the int Id
    public string    Name         { get; set; } = string.Empty;
    public string    CurrencyCode { get; set; } = string.Empty;
    public int       YearMinted   { get; set; }
    public DateTime? CreatedDate  { get; set; }
}
```

## Mapping (Entity ↔ DTO)

All mapping lives in `{AppName}.API/Mapping/`. Use extension methods for small projects, AutoMapper profiles for large ones.

```csharp
// API/Mapping/CoinMappingExtensions.cs
public static class CoinMappingExtensions
{
    public static CoinResponseDto ToResponseDto(this Coin coin) => new()
    {
        CoinGuid     = coin.Guid,
        Name         = coin.Name ?? string.Empty,
        CurrencyCode = coin.Currency.ToString(),
        YearMinted   = coin.YearMinted,
        CreatedDate  = coin.CreatedDate
    };
}
```
