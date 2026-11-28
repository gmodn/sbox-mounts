using System;
using System.Reflection;

namespace Source1;

/// <summary>
/// Mounts one Source 1 game directory configured in this file, without a Steam app ID.
/// </summary>
public sealed class CorehubSourceMount : SourceGameMount
{
	// Change this to the install root of the Source game you want to mount.
	// It should contain folders such as "hl2" and "materials", or the game's VPK archives.
	private const string LocalContentPath = @"D:\miscgames\Portal_2_3916_Jul_28_2009\Portal_2\game";

	private BaseFileSystem contentFileSystem;

	protected override string ContentDirectory => "portal2";
	public override string Ident => "p2corehub";
	public override string Title => "Portal 2 (Corehub Era)";
	public override long AppId => 0;
	public override long? SteamAppId => null;

	private protected override IEnumerable<ContentSource> FindContent( InitializeContext context )
	{
		DisposeFileSystem( contentFileSystem );
		contentFileSystem = null;

		if ( string.IsNullOrWhiteSpace( LocalContentPath ) || !System.IO.Directory.Exists( LocalContentPath ) )
		{
			Log.Warning( $"{Title}: set LocalContentPath in the core hub mount to a Source game install directory." );
			return null;
		}

		try
		{
			contentFileSystem = CreateLocalFileSystem( LocalContentPath );
			return ScanContent( contentFileSystem );
		}
		catch ( Exception e ) when ( e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException
			or MissingMethodException or TargetInvocationException )
		{
			DisposeFileSystem( contentFileSystem );
			contentFileSystem = null;
			Log.Warning( $"{Title}: could not open '{LocalContentPath}': {e.Message}" );
			return null;
		}
	}

	protected override void Shutdown()
	{
		base.Shutdown();
		DisposeFileSystem( contentFileSystem );
		contentFileSystem = null;
	}

	private static void DisposeFileSystem( BaseFileSystem fileSystem )
	{
		if ( fileSystem is IDisposable disposable )
			disposable.Dispose();
	}

	private static BaseFileSystem CreateLocalFileSystem( string path )
	{
		// LocalFileSystem exists in the host filesystem assembly, but its constructor is internal.
		// Use a read-only instance so the importer can scan and open game files without modifying them.
		var type = typeof( BaseFileSystem ).Assembly.GetType( "Sandbox.LocalFileSystem", throwOnError: true );
		var fileSystem = Activator.CreateInstance( type, BindingFlags.Instance | BindingFlags.NonPublic,
			binder: null, args: [path, true], culture: null ) as BaseFileSystem;
		return fileSystem ?? throw new InvalidOperationException( "The host did not create a local filesystem." );
	}
}
