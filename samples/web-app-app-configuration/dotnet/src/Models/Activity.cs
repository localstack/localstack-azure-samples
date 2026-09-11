namespace VacationPlanner.Models;

/// <summary>A planned vacation activity: the store's identifier plus the free-text description.</summary>
public sealed record Activity(string Id, string Text);
