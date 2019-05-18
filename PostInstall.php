<?php
/**
 * Executes after installing via Composer.
 *
 * @author kraftbj
 * @package Automattic/jetpack-standards
 */

namespace Automattic\Jetpack\Standards;

use Composer\Composer;
use Composer\IO\IOInterface;
use Composer\Plugin\PluginInterface;
use Composer\EventDispatcher\EventSubscriberInterface;

/**
 * Post Install class.
 * @package Automattic\jetpack-standards
 */
class PostInstall implements PluginInterface, EventSubscriberInterface {
	/**
	 * Composer Plugin activation.
	 *
	 * Unused. Intended for changing Composer internals, which we don't need.
	 *
	 * @param Composer $composer
	 * @param IOInterface $io
	 */
	public function activate(Composer $composer, IOInterface $io) {
	}

	/**
	 * Copies standards and GitHub templates from this plugin to the root directory of the included projects.
	 *
	 * Currently assumes that this file is at the third level of root.
	 */
	public static function post_install() {
		self::xcopy( ( __DIR__ ) . '/standards', dirname( dirname( dirname( __DIR__ ) ) ) );
		self::xcopy( ( __DIR__ ) . '/github', dirname( dirname( dirname( __DIR__ ) ) ) . '/.github' );
		self::xcopy( ( __DIR__ ) . '/bin', dirname( dirname( dirname( __DIR__ ) ) ) . '/bin' );
	}

	/**
	 * Copy a file, or recursively copy a folder and its contents
	 *
	 * @author      Aidan Lister <aidan@php.net>
	 * @version     1.0.1
	 * @link        http://aidanlister.com/2004/04/recursively-copying-directories-in-php/
	 * @param       string   $source    Source path
	 * @param       string   $dest      Destination path
	 * @return      bool     Returns TRUE on success, FALSE on failure
	 */
	private static function xcopy( $source, $dest ) {
		// Simple copy for a file
		if ( is_file( $source ) ) {
			return copy( $source, $dest );
		}
		// Make destination directory
		if ( ! is_dir( $dest ) ) {
			mkdir( $dest );
		}
		// Loop through the folder
		$dir = dir( $source );
		while ( false !== $entry = $dir->read() ) {
			// Skip pointers
			if ( $entry == '.' || $entry == '..' ) {
				continue;
			}
			// Deep copy directories
			self::xcopy("$source/$entry", "$dest/$entry" );
		}
		// Clean up
		$dir->close();
		return true;
	}

	/**
	 * Maps internal functions to Composer events.
	 *
	 * We specifically add both `post-install-cmd` and `post-update-cmd`.
	 * The former fires when composer install happens with a composer.lock.
	 * The second fires when composer install happens without a composer.lock (thus an update).
	 * @return array
	 */
	public static function getSubscribedEvents() {
		return array(
			'post-install-cmd' => 'post_install',
			'post-update-cmd'  => 'post_install',
		);
	}
}